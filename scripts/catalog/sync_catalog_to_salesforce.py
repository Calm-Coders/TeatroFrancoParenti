#!/usr/bin/env python3
"""Send the latest local TFP MySQL catalog snapshot to Salesforce."""

from __future__ import annotations

import argparse
import importlib
import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Iterator


SCRIPT_DIR = Path(__file__).resolve().parent
SALESFORCE_PROJECT_DIR = SCRIPT_DIR.parents[1]
DEFAULT_DB_PROJECT_DIR = Path.home() / "Desktop" / "DBTFP"
DEFAULT_ENDPOINT_PATH = "/services/apexrest/v1/inventories"


@dataclass(frozen=True)
class Snapshot:
    import_id: int
    product_count: int
    products: list[dict[str, Any]]


@dataclass(frozen=True)
class SalesforceSession:
    target_org: str
    username: str
    is_sandbox: bool
    sf_executable: str


def translated_value(value: Any, preferred_locale: str = "it") -> str | None:
    if not isinstance(value, dict):
        return None

    translations = value.get("translations")
    if not isinstance(translations, list):
        return None

    fallback: str | None = None
    for translation in translations:
        if not isinstance(translation, dict):
            continue
        translated = translation.get("value")
        if translated is None:
            continue
        translated_text = str(translated)
        if translation.get("locale") == preferred_locale:
            return translated_text
        if fallback is None:
            fallback = translated_text
    return fallback


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--db-project",
        type=Path,
        default=Path(os.getenv("TFP_DB_PROJECT", DEFAULT_DB_PROJECT_DIR)),
        help="DBTFP folder containing .env and import_catalog.py",
    )
    parser.add_argument(
        "--target-org",
        default=os.getenv("SALESFORCE_TARGET_ORG"),
        help="Salesforce CLI alias or username (defaults to the project's target-org)",
    )
    parser.add_argument("--execute", action="store_true", help="Perform Salesforce writes")
    parser.add_argument(
        "--check-auth",
        action="store_true",
        help="Validate Salesforce authentication during a dry run",
    )
    parser.add_argument(
        "--allow-production",
        action="store_true",
        help="Allow writes when the target org is not a sandbox",
    )
    parser.add_argument("--batch-size", type=int, default=10)
    parser.add_argument("--max-batch-bytes", type=int, default=2_000_000)
    parser.add_argument(
        "--product-id",
        action="append",
        type=str,
        dest="product_ids",
        help="Limit the sync to one product id; may be repeated",
    )
    return parser.parse_args()


def read_project_target_org() -> str:
    config_path = SALESFORCE_PROJECT_DIR / ".sf" / "config.json"
    if not config_path.exists():
        raise RuntimeError(
            "No --target-org was provided and .sf/config.json is missing. "
            "Run: sf config set target-org=\"TFA UAT\""
        )
    config = json.loads(config_path.read_text(encoding="utf-8"))
    target_org = config.get("target-org")
    if not target_org:
        raise RuntimeError("The Salesforce project has no target-org configured.")
    return str(target_org)


def load_db_modules(db_project: Path) -> tuple[Any, Any]:
    db_project = db_project.resolve()
    importer_path = db_project / "import_catalog.py"
    env_path = db_project / ".env"
    if not importer_path.exists() or not env_path.exists():
        raise RuntimeError(f"{db_project} is not a configured DBTFP project.")

    sys.path.insert(0, str(db_project))
    try:
        importer = importlib.import_module("import_catalog")
        mysql_connector = importlib.import_module("mysql.connector")
    finally:
        sys.path.pop(0)

    importer.load_dotenv(env_path)
    return importer, mysql_connector


def mysql_config() -> dict[str, Any]:
    required = ("MYSQL_HOST", "MYSQL_PORT", "MYSQL_USER", "MYSQL_PASSWORD", "MYSQL_DATABASE")
    missing = [name for name in required if not os.getenv(name)]
    if missing:
        raise RuntimeError(f"Missing DBTFP environment values: {', '.join(missing)}")
    return {
        "host": os.environ["MYSQL_HOST"],
        "port": int(os.environ["MYSQL_PORT"]),
        "user": os.environ["MYSQL_USER"],
        "password": os.environ["MYSQL_PASSWORD"],
        "database": os.environ["MYSQL_DATABASE"],
    }


def load_latest_snapshot(db_project: Path) -> Snapshot:
    importer, mysql_connector = load_db_modules(db_project)
    connection = mysql_connector.connect(**mysql_config())
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute(
            """SELECT id, product_count, raw_json
               FROM catalog_imports
               ORDER BY id DESC
               LIMIT 1"""
        )
        row = cursor.fetchone()
    finally:
        connection.close()

    if not row:
        raise RuntimeError("The database has no catalog snapshots.")

    payload = json.loads(row["raw_json"])
    try:
        catalog = payload["order"]["catalogData"]
    except (KeyError, TypeError) as exc:
        raise RuntimeError("The latest snapshot has no order.catalogData object.") from exc

    extracted = importer.extract(catalog)
    season_rank: dict[int, tuple[str, str, int]] = {}
    for season_id, season in extracted.seasons.items():
        season_rank[season_id] = (
            str(season.get("start") or ""),
            str(season.get("end") or ""),
            season_id,
        )

    # SecuTix can reuse the same product id in overlapping seasons. Salesforce's
    # Inventory_Id__c is globally unique, so retain the version belonging to the
    # newest season instead of letting payload traversal order decide the winner.
    products_by_id: dict[str, tuple[int, dict[str, Any]]] = {}
    for (season_id, product_id), product in sorted(extracted.products.items()):
        if not isinstance(product, dict):
            continue
        product_key = str(product_id)
        salesforce_product = dict(product)
        season = extracted.seasons.get(season_id) or {}
        # seasonId is contextual in the full catalog (the product is nested
        # under seasons[]) but explicit in the SecuTix webhook contract.
        salesforce_product.setdefault("seasonId", str(season_id))
        # Preserve the same season shape returned by the enrichment API so the
        # initial MySQL load can populate the human-readable season fields too.
        salesforce_product["season"] = {
            "id": season.get("id", season_id),
            "code": season.get("code"),
            "name_it": translated_value(season.get("externalName"), "it"),
            "start": season.get("start"),
            "end": season.get("end"),
        }
        previous = products_by_id.get(product_key)
        if previous is None or season_rank.get(season_id, ("", "", season_id)) > season_rank.get(
            previous[0], ("", "", previous[0])
        ):
            products_by_id[product_key] = (season_id, salesforce_product)

    products = [item[1] for item in products_by_id.values()]
    products.sort(key=lambda item: str(item.get("id", "")))
    return Snapshot(int(row["id"]), int(row["product_count"]), products)


def load_salesforce_session(target_org: str) -> SalesforceSession:
    sf_executable = shutil.which("sf.cmd" if os.name == "nt" else "sf")
    if not sf_executable:
        raise RuntimeError("Salesforce CLI was not found on PATH.")
    command = [
        sf_executable,
        "org",
        "display",
        "--target-org",
        target_org,
        "--json",
    ]
    completed = subprocess.run(
        command,
        cwd=SALESFORCE_PROJECT_DIR,
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"Salesforce authentication failed for {target_org}: {detail}")

    document = json.loads(completed.stdout)
    result = document.get("result", {})
    if not result.get("username"):
        raise RuntimeError(f"Salesforce CLI returned no session for {target_org}.")

    # `sf org display` does not expose isSandbox in every CLI version. Query the
    # org itself so the production-write interlock never depends on URL parsing.
    org_query = subprocess.run(
        [
            sf_executable,
            "data",
            "query",
            "--target-org",
            target_org,
            "--query",
            "SELECT IsSandbox FROM Organization LIMIT 1",
            "--json",
        ],
        cwd=SALESFORCE_PROJECT_DIR,
        capture_output=True,
        text=True,
        check=False,
    )
    if org_query.returncode != 0:
        detail = org_query.stderr.strip() or org_query.stdout.strip()
        raise RuntimeError(f"Could not verify the org type for {target_org}: {detail}")
    query_document = json.loads(org_query.stdout)
    records = query_document.get("result", {}).get("records", [])
    if not records or "IsSandbox" not in records[0]:
        raise RuntimeError(f"Could not determine whether {target_org} is a sandbox.")
    return SalesforceSession(
        target_org=target_org,
        username=str(result.get("username", target_org)),
        is_sandbox=bool(records[0]["IsSandbox"]),
        sf_executable=sf_executable,
    )


def encoded_size(products: Iterable[dict[str, Any]]) -> int:
    return len(json.dumps(list(products), ensure_ascii=False, separators=(",", ":")).encode("utf-8"))


def make_batches(
    products: list[dict[str, Any]], batch_size: int, max_batch_bytes: int
) -> Iterator[list[dict[str, Any]]]:
    if batch_size < 1 or max_batch_bytes < 1:
        raise ValueError("Batch limits must be positive numbers.")

    batch: list[dict[str, Any]] = []
    for product in products:
        candidate = [*batch, product]
        if batch and (len(candidate) > batch_size or encoded_size(candidate) > max_batch_bytes):
            yield batch
            batch = [product]
        else:
            batch = candidate
        if encoded_size(batch) > max_batch_bytes:
            product_id = product.get("id", "unknown")
            raise RuntimeError(
                f"Product {product_id} alone is larger than --max-batch-bytes={max_batch_bytes}."
            )
    if batch:
        yield batch


def post_batch(session: SalesforceSession, products: list[dict[str, Any]]) -> dict[str, Any]:
    body = json.dumps(products, ensure_ascii=False, separators=(",", ":"))
    completed = subprocess.run(
        [
            session.sf_executable,
            "api",
            "request",
            "rest",
            DEFAULT_ENDPOINT_PATH,
            "--target-org",
            session.target_org,
            "--method",
            "POST",
            "--header",
            "Content-Type: application/json; charset=utf-8",
            "--body",
            "-",
        ],
        cwd=SALESFORCE_PROJECT_DIR,
        input=body,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stdout.strip() or completed.stderr.strip()
        raise RuntimeError(f"Salesforce REST request failed: {detail}")
    result = json.loads(completed.stdout)
    if not result.get("success"):
        raise RuntimeError(f"Salesforce rejected the batch: {completed.stdout.strip()}")
    return result


def main() -> int:
    args = parse_args()
    target_org = args.target_org or read_project_target_org()
    snapshot = load_latest_snapshot(args.db_project)
    products = snapshot.products
    if args.product_ids:
        requested = set(args.product_ids)
        products = [product for product in products if str(product.get("id", "")) in requested]
        found = {str(product["id"]) for product in products}
        missing = requested - found
        if missing:
            raise RuntimeError(f"Product ids not present in snapshot {snapshot.import_id}: {sorted(missing)}")

    batches = list(make_batches(products, args.batch_size, args.max_batch_bytes))
    print(
        f"Snapshot {snapshot.import_id}: {len(products)} unique products "
        f"({snapshot.product_count} season-scoped rows), {len(batches)} Salesforce batches."
    )

    session: SalesforceSession | None = None
    if args.execute or args.check_auth:
        session = load_salesforce_session(target_org)
        org_kind = "sandbox" if session.is_sandbox else "production"
        print(f"Authenticated to {session.username} ({org_kind}) as target '{target_org}'.")

    if not args.execute:
        print("Dry run complete; no Salesforce records were changed. Add --execute to sync.")
        return 0

    assert session is not None
    if not session.is_sandbox and not args.allow_production:
        raise RuntimeError(
            "Production writes are locked. Use --allow-production only after validating the same sync in UAT."
        )

    processed = 0
    for index, batch in enumerate(batches, start=1):
        result = post_batch(session, batch)
        batch_count = int(result.get("processedProducts", len(batch)))
        processed += batch_count
        print(f"Batch {index}/{len(batches)}: {batch_count} products accepted.", flush=True)

    print(f"Salesforce sync complete: {processed} products accepted by {target_org}.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
