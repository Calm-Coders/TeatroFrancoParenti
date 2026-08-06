#!/usr/bin/env python3
"""Compare the latest local catalog relationship counts with Salesforce."""

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
    parser.add_argument(
        "--db-project",
        type=Path,
        default=Path(os.getenv("TFP_DB_PROJECT", DEFAULT_DB_PROJECT_DIR)),
    )
    parser.add_argument("--target-org", default=os.getenv("SALESFORCE_TARGET_ORG"))
    return parser.parse_args()


def expected_counts(products: list[dict[str, Any]]) -> dict[str, int]:
    def typed(field: str) -> list[dict[str, Any]]:
        return [product for product in products if isinstance(product.get(field), dict) and product[field]]

    events = typed("event")
    season_tickets = typed("seasonTicket")
    season_ticket_subjects = [
        subject
        for product in season_tickets
        for subject in product["seasonTicket"].get("seasonTicketSubjects") or []
        if isinstance(subject, dict)
    ]
    return {
        "inventories": len(products),
        "missing_season": 0,
        "missing_season_metadata": 0,
        "events": len(events),
        "memberships": len(typed("membership")),
        "packs": len(typed("pack")),
        "season_tickets": len(season_tickets),
        "season_ticket_subjects": len(season_ticket_subjects),
        "season_ticket_lines": (
            sum(
                len(product["seasonTicket"].get("seasonTicketLines") or [])
                for product in season_tickets
            )
            + sum(len(subject.get("seasonTicketLines") or []) for subject in season_ticket_subjects)
        ),
        "missing_line_subject": 0,
        "missing_line_target": 0,
        "performances": sum(len(product["event"].get("performances") or []) for product in events),
    }


def query_count(session: sync.SalesforceSession, soql: str) -> int:
    completed = subprocess.run(
        [
            session.sf_executable,
            "data",
            "query",
            "--target-org",
            session.target_org,
            "--query",
            soql,
            "--json",
        ],
        cwd=sync.SALESFORCE_PROJECT_DIR,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stdout.strip() or completed.stderr.strip()
        raise RuntimeError(f"Salesforce count query failed: {detail}")
    return int(json.loads(completed.stdout)["result"]["totalSize"])


def main() -> int:
    args = parse_args()
    target_org = args.target_org or sync.read_project_target_org()
    snapshot = sync.load_latest_snapshot(args.db_project)
    session = sync.load_salesforce_session(target_org)
    ids = ",".join(f"{int(product['id'])}.0" for product in snapshot.products)
    scope = f"({ids})"
    queries = {
        "inventories": f"SELECT COUNT() FROM Inventory__c WHERE Inventory_Id__c IN {scope}",
        "missing_season": (
            f"SELECT COUNT() FROM Inventory__c WHERE Inventory_Id__c IN {scope} "
            "AND Season_Id__c = null"
        ),
        "missing_season_metadata": (
            f"SELECT COUNT() FROM Inventory__c WHERE Inventory_Id__c IN {scope} "
            "AND (Season_Code__c = null OR Season_Name__c = null "
            "OR Season_Start__c = null OR Season_End__c = null)"
        ),
        "events": (
            "SELECT COUNT() FROM Inventory_Event__c "
            f"WHERE Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "memberships": (
            "SELECT COUNT() FROM Membership__c "
            f"WHERE Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "packs": f"SELECT COUNT() FROM Pack__c WHERE Inventory__r.Inventory_Id__c IN {scope}",
        "season_tickets": (
            "SELECT COUNT() FROM Season_Ticket__c "
            f"WHERE Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "season_ticket_subjects": (
            "SELECT COUNT() FROM Season_Ticket_Subject__c "
            f"WHERE Season_Ticket__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "season_ticket_lines": (
            "SELECT COUNT() FROM Season_Ticket_Line__c "
            f"WHERE Season_Ticket__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "missing_line_subject": (
            "SELECT COUNT() FROM Season_Ticket_Line__c "
            f"WHERE Season_Ticket__r.Inventory__r.Inventory_Id__c IN {scope} "
            "AND Placement_Type__c = 'subject' AND Subject__c = null"
        ),
        "missing_line_target": (
            "SELECT COUNT() FROM Season_Ticket_Line__c "
            f"WHERE Season_Ticket__r.Inventory__r.Inventory_Id__c IN {scope} "
            "AND Target_Inventory__c = null"
        ),
        "performances": (
            "SELECT COUNT() FROM Performance__c "
            f"WHERE Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
    }

    expected = expected_counts(snapshot.products)
    actual = {name: query_count(session, query) for name, query in queries.items()}
    print(f"Snapshot {snapshot.import_id} vs {target_org} ({session.username})")
    print("relationship       expected  actual  result")
    mismatches = 0
    for name in queries:
        passed = expected[name] == actual[name]
        mismatches += 0 if passed else 1
        print(f"{name:18} {expected[name]:8} {actual[name]:7}  {'OK' if passed else 'MISMATCH'}")
    if mismatches:
        print(f"Verification failed: {mismatches} relationship counts differ.", file=sys.stderr)
        return 1
    print("Verification complete: every relationship count matches.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
