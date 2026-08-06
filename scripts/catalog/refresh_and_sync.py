#!/usr/bin/env python3
"""Refresh the local TFP catalog snapshot, then optionally sync it to Salesforce."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
SYNC_SCRIPT = SCRIPT_DIR / "sync_catalog_to_salesforce.py"
DEFAULT_DB_PROJECT_DIR = Path.home() / "Desktop" / "DBTFP"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--db-project",
        type=Path,
        default=Path(os.getenv("TFP_DB_PROJECT", DEFAULT_DB_PROJECT_DIR)),
    )
    parser.add_argument("--target-org", default=os.getenv("SALESFORCE_TARGET_ORG"))
    parser.add_argument("--execute", action="store_true", help="Write the refreshed catalog to Salesforce")
    parser.add_argument("--allow-production", action="store_true")
    parser.add_argument("--batch-size", type=int, default=10)
    parser.add_argument("--max-batch-bytes", type=int, default=2_000_000)
    return parser.parse_args()


def run(command: list[str], cwd: Path) -> None:
    completed = subprocess.run(command, cwd=cwd, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"Command failed with exit code {completed.returncode}: {' '.join(command)}")


def main() -> int:
    args = parse_args()
    db_project = args.db_project.resolve()
    importer = db_project / "import_catalog.py"
    if not importer.exists():
        raise RuntimeError(f"Cannot find {importer}")

    print("Step 1/2: refreshing the local MySQL catalog ...", flush=True)
    run([sys.executable, str(importer)], db_project)

    print("Step 2/2: validating or syncing Salesforce ...", flush=True)
    sync_command = [
        sys.executable,
        str(SYNC_SCRIPT),
        "--db-project",
        str(db_project),
        "--batch-size",
        str(args.batch_size),
        "--max-batch-bytes",
        str(args.max_batch_bytes),
    ]
    if args.target_org:
        sync_command.extend(["--target-org", args.target_org])
    if args.execute:
        sync_command.append("--execute")
    else:
        sync_command.append("--check-auth")
    if args.allow_production:
        sync_command.append("--allow-production")
    run(sync_command, SCRIPT_DIR)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
