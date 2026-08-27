#!/usr/bin/env python3
"""Restore Performance price audit JSON from MySQL without replacing Performances."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

import sync_catalog_to_salesforce as sync


DEFAULT_DB_PROJECT_DIR = Path.home() / "Desktop" / "DBTFP"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db-project", type=Path, default=DEFAULT_DB_PROJECT_DIR)
    parser.add_argument("--target-org", default=os.getenv("SALESFORCE_TARGET_ORG"))
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--allow-production", action="store_true")
    parser.add_argument("--batch-size", type=int, default=150)
    return parser.parse_args()


def sf_query(session: sync.SalesforceSession, soql: str) -> list[dict[str, Any]]:
    completed = subprocess.run(
        [session.sf_executable, "data", "query", "--target-org", session.target_org,
         "--query", soql, "--json"],
        cwd=sync.SALESFORCE_PROJECT_DIR, capture_output=True, text=True, encoding="utf-8"
    )
    if completed.returncode:
        raise RuntimeError(completed.stdout.strip() or completed.stderr.strip())
    return json.loads(completed.stdout)["result"]["records"]


def load_audience_legends(db_project: Path, import_id: int) -> dict[str, dict[str, Any]]:
    _, mysql_connector = sync.load_db_modules(db_project)
    connection = mysql_connector.connect(**sync.mysql_config())
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute(
            "SELECT source_id, metadata_json FROM audience_subcategories WHERE import_id = %s",
            (import_id,),
        )
        legends: dict[str, dict[str, Any]] = {}
        for row in cursor.fetchall():
            payload = row["metadata_json"]
            if isinstance(payload, str):
                payload = json.loads(payload)
            if isinstance(payload, dict):
                legends[str(row["source_id"])] = payload
        return legends
    finally:
        connection.close()


def desired_performances(snapshot: sync.Snapshot, legends: dict[str, dict[str, Any]]) -> dict[tuple[str, str], dict[str, str]]:
    desired: dict[tuple[str, str], dict[str, str]] = {}
    for product in snapshot.products:
        product_id = str(product["id"])
        event = product.get("event")
        performances = event.get("performances") if isinstance(event, dict) else None
        if not isinstance(performances, list):
            continue
        for performance in performances:
            if not isinstance(performance, dict) or performance.get("id") is None:
                continue
            prices = [item for item in performance.get("prices") or [] if isinstance(item, dict)]
            audience_ids = {
                str(item["audSubCatId"])
                for item in prices
                if item.get("audSubCatId") is not None
            }
            tariff_legend = [legends[value] for value in sorted(audience_ids) if value in legends]
            desired[(product_id, str(performance["id"]))] = {
                "Prices__c": json.dumps(prices, ensure_ascii=False, separators=(",", ":")),
                "Tariff_Legend__c": json.dumps(tariff_legend, ensure_ascii=False, separators=(",", ":")),
            }
    return desired


def update_batch(session: sync.SalesforceSession, records: list[dict[str, Any]]) -> None:
    body = json.dumps({"allOrNone": True, "records": records}, ensure_ascii=False, separators=(",", ":"))
    completed = subprocess.run(
        [session.sf_executable, "api", "request", "rest", "/services/data/v65.0/composite/sobjects",
         "--target-org", session.target_org, "--method", "PATCH",
         "--header", "Content-Type: application/json; charset=utf-8", "--body", "-"],
        cwd=sync.SALESFORCE_PROJECT_DIR, input=body, capture_output=True,
        text=True, encoding="utf-8"
    )
    if completed.returncode:
        raise RuntimeError(completed.stdout.strip() or completed.stderr.strip())
    response = json.loads(completed.stdout)
    failures = [item for item in response if not item.get("success")]
    if failures:
        raise RuntimeError(f"Salesforce rejected price audit updates: {failures[:3]}")


def main() -> int:
    args = parse_args()
    target_org = args.target_org or sync.read_project_target_org()
    snapshot = sync.load_latest_snapshot(args.db_project)
    legends = load_audience_legends(args.db_project, snapshot.import_id)
    desired = desired_performances(snapshot, legends)
    session = sync.load_salesforce_session(target_org)
    if not session.is_sandbox and not args.allow_production:
        raise RuntimeError("Production writes are locked; validate this backfill in UAT first.")

    rows = sf_query(
        session,
        "SELECT Id, Performance_Id__c, Inventory_Event__r.Inventory__r.Inventory_Id__c FROM Performance__c",
    )
    updates: list[dict[str, Any]] = []
    missing: list[tuple[str, str]] = []
    matched: set[tuple[str, str]] = set()
    for row in rows:
        inventory = row.get("Inventory_Event__r", {}).get("Inventory__r", {})
        product_id = inventory.get("Inventory_Id__c")
        performance_id = row.get("Performance_Id__c")
        if product_id is None or performance_id is None:
            continue
        key = (str(product_id), str(performance_id))
        payload = desired.get(key)
        if payload is None:
            continue
        matched.add(key)
        updates.append({"attributes": {"type": "Performance__c"}, "Id": row["Id"], **payload})
    missing.extend(sorted(set(desired) - matched))

    priced = sum(len(json.loads(item["Prices__c"])) > 0 for item in updates)
    print(
        f"Snapshot {snapshot.import_id}: matched {len(updates)} Performances; "
        f"{priced} contain prices; {len(missing)} missing in Salesforce."
    )
    if missing:
        raise RuntimeError(f"Performance mapping is incomplete; first missing keys: {missing[:5]}")
    if not args.execute:
        print("Dry run complete; no Salesforce records changed. Add --execute to apply.")
        return 0
    for start in range(0, len(updates), args.batch_size):
        batch = updates[start:start + args.batch_size]
        update_batch(session, batch)
        print(f"Updated {min(start + len(batch), len(updates))}/{len(updates)} Performance audit rows.", flush=True)
    print("Price audit backfill complete; run PerformancePriceBackfillBatch to normalize relationships.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
