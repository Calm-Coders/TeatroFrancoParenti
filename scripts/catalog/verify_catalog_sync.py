#!/usr/bin/env python3
"""Compare the latest local catalog relationship counts with Salesforce."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
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
    memberships = typed("membership")
    packs = typed("pack")
    season_tickets = typed("seasonTicket")
    package_lines = [
        line
        for product in packs
        for line in product["pack"].get("packageLine") or []
        if isinstance(line, dict) and line.get("packageLineId") is not None
    ]
    season_ticket_subjects = [
        subject
        for product in season_tickets
        for subject in product["seasonTicket"].get("seasonTicketSubjects") or []
        if isinstance(subject, dict)
    ]
    product_sale_periods = [
        period
        for product in products
        for period in product.get("salePeriods") or []
        if isinstance(period, dict)
    ]
    performance_sale_periods = [
        period
        for product in events
        for performance in product["event"].get("performances") or []
        if isinstance(performance, dict)
        for period in performance.get("salePeriods") or []
        if isinstance(period, dict)
    ]
    membership_items = [
        item
        for product in memberships
        for item in product["membership"].get("items") or []
        if isinstance(item, dict) and item.get("itemId") is not None
    ]
    membership_item_prices = [
        price
        for item in membership_items
        for price in item.get("itemPrices") or []
        if isinstance(price, dict)
    ]
    membership_sale_periods = [
        period
        for price in membership_item_prices
        for period in price.get("salePeriods") or []
        if isinstance(period, dict)
    ]

    def restriction_count(periods: list[dict[str, Any]], keys: tuple[str, ...]) -> int:
        total = 0
        for period in periods:
            values: set[str] = set()
            for key in keys:
                for value in period.get(key) or []:
                    if isinstance(value, dict):
                        external_id = value.get("id")
                        code = value.get("code")
                        normalized = str(external_id) if external_id is not None else str(code or "")
                    else:
                        normalized = str(value)
                    if normalized:
                        values.add(normalized)
            total += len(values)
        return total

    all_sale_periods = (
        product_sale_periods + performance_sale_periods + membership_sale_periods
    )
    performance_prices = [
        price
        for product in events
        for performance in product["event"].get("performances") or []
        if isinstance(performance, dict)
        for price in performance.get("prices") or []
        if isinstance(price, dict)
    ]
    performance_price_charges = [
        charge
        for price in performance_prices
        for charge in price.get("chargesAmounts") or []
        if isinstance(charge, dict)
    ]

    def reference_keys(values: list[Any], id_key: str = "id", code_key: str = "code") -> set[str]:
        keys: set[str] = set()
        for value in values:
            if isinstance(value, dict):
                external_id = value.get(id_key)
                code = value.get(code_key)
                key = str(external_id) if external_id is not None else (f"CODE:{code}" if code else "")
            else:
                key = str(value) if value is not None else ""
            if key:
                keys.add(key)
        return keys

    audience_reference_keys = reference_keys(
        [
            value
            for period in all_sale_periods
            for key in ("audienceSubCatIds", "tariffs", "ticketTypes")
            for value in period.get(key) or []
        ]
    )
    audience_reference_keys.update(
        str(price["audSubCatId"])
        for price in performance_prices + membership_item_prices
        if price.get("audSubCatId") is not None
    )
    audience_reference_keys.update(
        str(line["forcedAudSubCatId"])
        for line in package_lines
        if line.get("forcedAudSubCatId") is not None
    )
    charge_reference_keys = reference_keys(
        performance_price_charges, id_key="chargesId", code_key="component"
    )
    performance_seat_category_keys: set[str] = set()
    performance_seat_category_links = 0
    venue_location_keys: set[str] = set()
    for product in events:
        for performance in product["event"].get("performances") or []:
            if not isinstance(performance, dict):
                continue
            location = performance.get("location")
            site = performance.get("site")
            space = performance.get("space")
            if any(isinstance(value, dict) for value in (location, site, space)):
                location = location if isinstance(location, dict) else {}
                site = site if isinstance(site, dict) else {}
                space = space if isinstance(space, dict) else {}
                site_code = site.get("code") or location.get("siteCode") or performance.get("siteCode") or "NONE"
                space_code = space.get("code") or location.get("spaceCode") or performance.get("spaceCode") or "NONE"
                venue_location_keys.add(f"{site_code}|{space_code}")
            performance_keys: set[str] = set()
            for category in performance.get("seatCategories") or []:
                if not isinstance(category, dict):
                    continue
                category_id = category.get("id")
                key = str(category_id) if category_id is not None else f"CODE:{category.get('code') or ''}"
                if key and key != "CODE:":
                    performance_keys.add(key)
                    performance_seat_category_keys.add(key)
            performance_seat_category_links += len(performance_keys)
    return {
        "inventories": len(products),
        "missing_season": 0,
        "missing_season_metadata": 0,
        "inventory_sale_periods": len(product_sale_periods),
        "performance_sale_periods": len(performance_sale_periods),
        "membership_sale_periods": len(membership_sale_periods),
        "sale_period_audiences": restriction_count(
            all_sale_periods, ("audienceSubCatIds", "tariffs", "ticketTypes")
        ),
        "sale_period_seats": restriction_count(
            all_sale_periods, ("seatCategoryIds", "seatCategories")
        ),
        "missing_sale_period_parent": 0,
        "missing_sale_period_channel": 0,
        "seat_categories": len(performance_seat_category_keys),
        "performance_seat_categories": performance_seat_category_links,
        "missing_performance_seat_category_lookup": 0,
        "venue_locations": len(venue_location_keys),
        "missing_performance_location_lookup": 0,
        "audience_sub_categories": len(audience_reference_keys),
        "missing_sale_period_audience_lookup": 0,
        "performance_prices": len(performance_prices),
        "missing_price_seat_lookup": 0,
        "missing_price_audience_lookup": 0,
        "membership_items": len(membership_items),
        "membership_item_prices": len(membership_item_prices),
        "missing_membership_price_audience_lookup": 0,
        "charge_components": len(charge_reference_keys),
        "performance_price_charges": len(performance_price_charges),
        "missing_price_charge_lookup": 0,
        "events": len(events),
        "memberships": len(memberships),
        "packs": len(packs),
        "package_lines": len(package_lines),
        "missing_package_line_audience": 0,
        "missing_package_line_target": 0,
        "missing_package_line_parent": 0,
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
    # The full catalog scope contains enough 14-digit IDs to exceed Windows'
    # command-line length limit. Pass SOQL through a temporary file instead.
    with tempfile.TemporaryDirectory(prefix="tfp-soql-") as temp_dir:
        query_path = Path(temp_dir) / "query.soql"
        query_path.write_text(soql, encoding="utf-8")
        completed = subprocess.run(
            [
                session.sf_executable,
                "data",
                "query",
                "--target-org",
                session.target_org,
                "--file",
                str(query_path),
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
    expected_audience_keys = {
        str(value.get("id")) if isinstance(value, dict) and value.get("id") is not None
        else f"CODE:{value.get('code')}" if isinstance(value, dict) and value.get("code")
        else str(value) if value is not None and not isinstance(value, dict)
        else ""
        for product in snapshot.products
        for period in (
            list(product.get("salePeriods") or [])
            + [
                nested_period
                for performance in (product.get("event") or {}).get("performances") or []
                if isinstance(performance, dict)
                for nested_period in performance.get("salePeriods") or []
            ]
            + [
                nested_period
                for item in (product.get("membership") or {}).get("items") or []
                if isinstance(item, dict)
                for price in item.get("itemPrices") or []
                if isinstance(price, dict)
                for nested_period in price.get("salePeriods") or []
            ]
        )
        if isinstance(period, dict)
        for key in ("audienceSubCatIds", "tariffs", "ticketTypes")
        for value in period.get(key) or []
    }
    expected_audience_keys.update(
        str(price["audSubCatId"])
        for product in snapshot.products
        for performance in (product.get("event") or {}).get("performances") or []
        if isinstance(performance, dict)
        for price in performance.get("prices") or []
        if isinstance(price, dict) and price.get("audSubCatId") is not None
    )
    expected_audience_keys.update(
        str(price["audSubCatId"])
        for product in snapshot.products
        for item in (product.get("membership") or {}).get("items") or []
        if isinstance(item, dict)
        for price in item.get("itemPrices") or []
        if isinstance(price, dict) and price.get("audSubCatId") is not None
    )
    expected_audience_keys.update(
        str(line["forcedAudSubCatId"])
        for product in snapshot.products
        for line in (product.get("pack") or {}).get("packageLine") or []
        if isinstance(line, dict) and line.get("forcedAudSubCatId") is not None
    )
    expected_audience_keys.discard("")
    audience_scope = ",".join(
        f"'{key.replace(chr(39), chr(92) + chr(39))}'"
        for key in sorted(expected_audience_keys)
    ) or "'__NONE__'"
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
        "inventory_sale_periods": (
            "SELECT COUNT() FROM Sale_Period__c "
            f"WHERE Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "performance_sale_periods": (
            "SELECT COUNT() FROM Sale_Period__c "
            f"WHERE Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "membership_sale_periods": (
            "SELECT COUNT() FROM Sale_Period__c WHERE "
            f"Membership_Item_Price__r.Membership_Item__r.Membership__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "sale_period_audiences": (
            "SELECT COUNT() FROM Sale_Period_Audience__c WHERE "
            f"Sale_Period__r.Inventory__r.Inventory_Id__c IN {scope} OR "
            f"Sale_Period__r.Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope} OR "
            f"Sale_Period__r.Membership_Item_Price__r.Membership_Item__r.Membership__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "sale_period_seats": (
            "SELECT COUNT() FROM Sale_Period_Seat_Category__c WHERE "
            f"Sale_Period__r.Inventory__r.Inventory_Id__c IN {scope} OR "
            f"Sale_Period__r.Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope} OR "
            f"Sale_Period__r.Membership_Item_Price__r.Membership_Item__r.Membership__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "missing_sale_period_parent": (
            "SELECT COUNT() FROM Sale_Period__c WHERE Inventory__c = null "
            "AND Performance__c = null AND Membership_Item_Price__c = null"
        ),
        "missing_sale_period_channel": (
            "SELECT COUNT() FROM Sale_Period__c WHERE Sales_Channel__c = null AND ("
            f"Inventory__r.Inventory_Id__c IN {scope} OR "
            f"Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope} OR "
            f"Membership_Item_Price__r.Membership_Item__r.Membership__r.Inventory__r.Inventory_Id__c IN {scope})"
        ),
        "seat_categories": (
            "SELECT Seat_Category__c FROM Performance_Seat_Category__c WHERE "
            f"Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope} "
            "GROUP BY Seat_Category__c"
        ),
        "performance_seat_categories": (
            "SELECT COUNT() FROM Performance_Seat_Category__c WHERE "
            f"Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "missing_performance_seat_category_lookup": (
            "SELECT COUNT() FROM Performance_Seat_Category__c WHERE "
            f"Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope} "
            "AND Seat_Category__c = null"
        ),
        "venue_locations": "SELECT COUNT() FROM Venue_Location__c",
        "missing_performance_location_lookup": (
            "SELECT COUNT() FROM Performance__c WHERE "
            f"Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope} "
            "AND Venue_Location__c = null"
        ),
        "audience_sub_categories": (
            "SELECT COUNT() FROM Audience_Sub_Category__c "
            f"WHERE Audience_Key__c IN ({audience_scope})"
        ),
        "missing_sale_period_audience_lookup": (
            "SELECT COUNT() FROM Sale_Period_Audience__c WHERE "
            f"(Sale_Period__r.Inventory__r.Inventory_Id__c IN {scope} OR "
            f"Sale_Period__r.Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope} OR "
            f"Sale_Period__r.Membership_Item_Price__r.Membership_Item__r.Membership__r.Inventory__r.Inventory_Id__c IN {scope}) "
            "AND Audience_Sub_Category__c = null"
        ),
        "performance_prices": (
            "SELECT COUNT() FROM Performance_Price__c WHERE "
            f"Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "missing_price_seat_lookup": (
            "SELECT COUNT() FROM Performance_Price__c WHERE "
            f"Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope} "
            "AND Seat_Category__c = null"
        ),
        "missing_price_audience_lookup": (
            "SELECT COUNT() FROM Performance_Price__c WHERE "
            f"Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope} "
            "AND Audience_Sub_Category__c = null"
        ),
        "membership_items": (
            "SELECT COUNT() FROM Membership_Item__c "
            f"WHERE Membership__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "membership_item_prices": (
            "SELECT COUNT() FROM Membership_Item_Price__c WHERE "
            f"Membership_Item__r.Membership__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "missing_membership_price_audience_lookup": (
            "SELECT COUNT() FROM Membership_Item_Price__c WHERE "
            f"Membership_Item__r.Membership__r.Inventory__r.Inventory_Id__c IN {scope} "
            "AND Audience_Subcategory_Id__c != null AND Audience_Sub_Category__c = null"
        ),
        "charge_components": (
            "SELECT Charge_Component__c FROM Performance_Price_Charge__c WHERE "
            f"Performance_Price__r.Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope} "
            "GROUP BY Charge_Component__c"
        ),
        "performance_price_charges": (
            "SELECT COUNT() FROM Performance_Price_Charge__c WHERE "
            f"Performance_Price__r.Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "missing_price_charge_lookup": (
            "SELECT COUNT() FROM Performance_Price_Charge__c WHERE "
            f"Performance_Price__r.Performance__r.Inventory_Event__r.Inventory__r.Inventory_Id__c IN {scope} "
            "AND Charge_Component__c = null"
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
        "package_lines": (
            "SELECT COUNT() FROM Package_Line__c "
            f"WHERE Pack__r.Inventory__r.Inventory_Id__c IN {scope}"
        ),
        "missing_package_line_audience": (
            "SELECT COUNT() FROM Package_Line__c "
            f"WHERE Pack__r.Inventory__r.Inventory_Id__c IN {scope} "
            "AND Forced_Audience_Subcategory_Id__c != null "
            "AND Forced_Audience_Sub_Category__c = null"
        ),
        "missing_package_line_target": (
            "SELECT COUNT() FROM Package_Line__c "
            f"WHERE Pack__r.Inventory__r.Inventory_Id__c IN {scope} "
            "AND Target_Product_Id__c != null AND Target_Inventory__c = null"
        ),
        "missing_package_line_parent": (
            "SELECT COUNT() FROM Package_Line__c "
            f"WHERE Pack__r.Inventory__r.Inventory_Id__c IN {scope} "
            "AND Parent_Package_Line_Id__c != null AND Parent_Package_Line__c = null"
        ),
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
    print("relationship                                expected  actual  result")
    mismatches = 0
    for name in queries:
        passed = expected[name] == actual[name]
        mismatches += 0 if passed else 1
        print(f"{name:42} {expected[name]:8} {actual[name]:7}  {'OK' if passed else 'MISMATCH'}")
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
