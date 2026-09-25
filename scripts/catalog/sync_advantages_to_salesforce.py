"""Reconcile full SecuTix GET Catalog advantages into Salesforce.

Dry-run by default. A successful execution upserts the current catalog snapshot;
it never deletes historical rows without a separate reviewed migration.
"""

import argparse
import hashlib
import json
import os
import subprocess
import tempfile
import urllib.request
from pathlib import Path

API = "/services/data/v65.0"
BOOL = {
    "mandatoryContact": "Mandatory_Contact__c",
    "exclusive": "Exclusive__c",
    "autoPromote": "Auto_Promote__c",
    "allowPurchaseCulturalContact": "Allow_Purchase_Cultural_Contact__c",
    "quotaPerTimeslot": "Quota_Per_Timeslot__c",
    "singleSeatCatPerPerformance": "Single_Seat_Category_Per_Performance__c",
}
SCALAR = {
    "code": "Code__c", "state": "State__c",
    "advantageType": "Advantage_Type__c",
    "advantageTargetType": "Target_Type__c", "accessCode": "Access_Code__c",
    "contactLimitation": "Contact_Limitation__c",
    "performanceEndDateType": "Performance_End_Date_Type__c",
    "maxOrderQuantity": "Max_Order_Quantity__c",
    "maxQuantityPerPerformance": "Max_Quantity_Per_Performance__c",
    "start": "Start__c",
}


def translated(value, locale):
    for item in (value or {}).get("translations") or []:
        if item.get("locale", "").lower().split("_")[0] == locale:
            return item.get("value")
    return None


def parse_catalog(document):
    seasons = document["order"]["catalogData"]["seasons"]
    if not seasons:
        raise ValueError("Catalog has no seasons")
    parents, links = [], []
    seen_parents, seen_links = set(), set()
    for season in seasons:
        season_id = str(season["id"])
        if not season_id or not season.get("advantages"):
            raise ValueError(f"Season {season_id} has no advantages; refusing partial snapshot")
        for advantage in season["advantages"]:
            advantage_id = str(advantage["id"])
            key = f"{season_id}|{advantage_id}"
            if key in seen_parents:
                raise ValueError(f"Duplicate advantage {key}")
            seen_parents.add(key)
            name_it = translated(advantage.get("externalName"), "it")
            name_en = translated(advantage.get("externalName"), "en")
            row = {
                "attributes": {"type": "Catalog_Advantage__c"},
                "Name": ((name_it or name_en or advantage.get("code") or advantage_id)[:80]),
                "Advantage_Key__c": key,
                "Advantage_Id__c": advantage_id,
                "Season_Id__c": season_id,
                "Name_IT__c": name_it,
                "Name_EN__c": name_en,
                "Description_IT__c": translated(advantage.get("externalDescription"), "it"),
                "Description_EN__c": translated(advantage.get("externalDescription"), "en"),
                "Free_Shipment_Mode_Ids__c": json.dumps(advantage.get("freeShipmentModeIds") or [], ensure_ascii=False),
                "Raw_JSON__c": json.dumps({k: v for k, v in advantage.items() if k != "products"}, ensure_ascii=False, separators=(",", ":")),
            }
            for source, target in SCALAR.items():
                row[target] = advantage.get(source)
            for source, target in BOOL.items():
                row[target] = bool(advantage.get(source))
            if row["Start__c"] and row["Start__c"].endswith("Z"):
                row["Start__c"] = row["Start__c"][:-1] + "+00:00"
            parents.append(row)
            for position, product in enumerate(advantage.get("products") or [], 1):
                product_id = str(product["id"])
                link_key = f"{key}|{product_id}"
                if link_key in seen_links:
                    raise ValueError(f"Duplicate advantage/product {link_key}")
                seen_links.add(link_key)
                links.append({
                    "attributes": {"type": "Catalog_Advantage_Product__c"},
                    "Name": f"{advantage.get('code') or advantage_id} / {product.get('code') or product_id}"[:80],
                    "Relationship_Key__c": link_key,
                    "Season_Id__c": season_id,
                    "Product_Id__c": product_id,
                    "Product_Code__c": product.get("code"),
                    "Sequence__c": position,
                    "_parent_key": key,
                })
    return parents, links


def sf(arguments, org):
    process = subprocess.run(["sf.cmd" if os.name == "nt" else "sf", *arguments, "--target-org", org, "--json"],
                             text=True, encoding="utf-8", capture_output=True, check=False)
    try:
        result = json.loads(process.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Salesforce CLI returned invalid JSON: {process.stderr[:300]}") from exc
    if process.returncode or result.get("status"):
        raise RuntimeError(f"Salesforce CLI error: {json.dumps(result.get('result'), ensure_ascii=False)[:1500]}")
    return result["result"]


def query_all(soql, org):
    result = sf(["data", "query", "--query", soql], org)
    if not result.get("done"):
        raise RuntimeError("SOQL result was truncated")
    return result["records"]


def upsert_collection(object_name, external_field, rows, org):
    endpoint = f"{API}/composite/sobjects/{object_name}/{external_field}"
    for start in range(0, len(rows), 200):
        batch = rows[start:start + 200]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "request.json"
            path.write_text(json.dumps({"allOrNone": True, "records": batch}, ensure_ascii=True), encoding="ascii")
            response = sf(["api", "request", "rest", endpoint, "--method", "PATCH", "--body", "@" + str(path)], org)
        body = response.get("body")
        if response.get("statusCode") not in (200, 201) or not isinstance(body, list):
            raise RuntimeError(f"Upsert failed: {json.dumps(response, ensure_ascii=False)[:1800]}")
        errors = [item for item in body if not item.get("success")]
        if errors:
            raise RuntimeError(f"Upsert failed: {json.dumps(errors, ensure_ascii=False)[:1800]}")
        print(f"Upserted {object_name}: {start + len(batch)}/{len(rows)}")


def update_collection(object_name, rows, org):
    endpoint = f"{API}/composite/sobjects"
    for start in range(0, len(rows), 200):
        batch = rows[start:start + 200]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "request.json"
            path.write_text(json.dumps({"allOrNone": True, "records": batch}, ensure_ascii=True), encoding="ascii")
            response = sf(["api", "request", "rest", endpoint, "--method", "PATCH", "--body", "@" + str(path)], org)
        body = response.get("body")
        if response.get("statusCode") not in (200, 201) or not isinstance(body, list):
            raise RuntimeError(f"Update failed: {json.dumps(response, ensure_ascii=False)[:1800]}")
        errors = [item for item in body if not item.get("success")]
        if errors:
            raise RuntimeError(f"Update failed: {json.dumps(errors, ensure_ascii=False)[:1800]}")
        print(f"Cleaned {object_name}: {start + len(batch)}/{len(rows)}")


def legacy_updates(parents, links, inventory):
    by_key = {row["Advantage_Key__c"]: row for row in parents}
    wanted = {}
    for link in links:
        advantage = by_key[link["_parent_key"]]
        key = (link["Season_Id__c"], link["Product_Id__c"])
        wanted.setdefault(key, []).append({
            "id": int(advantage["Advantage_Id__c"]),
            "code": advantage["Code__c"],
            "name_it": advantage["Name_IT__c"],
            "name_en": advantage["Name_EN__c"],
            "advantageTargetType": advantage["Target_Type__c"],
        })
    for values in wanted.values():
        values.sort(key=lambda row: row["id"])
    snapshot_seasons = {row["Season_Id__c"] for row in parents}
    updates, backup = [], []
    for row in inventory:
        if str(row.get("Season_Id__c")) not in snapshot_seasons or not row.get("Inventory_Id__c"):
            continue
        key = (str(row["Season_Id__c"]), str(row["Inventory_Id__c"]))
        desired = wanted.get(key, [])
        old_text = row.get("Product_Advantages__c")
        old = json.loads(old_text) if old_text else []
        if not isinstance(old, list):
            raise ValueError(f"Invalid existing Product_Advantages__c on {row['Id']}")
        if sorted(old, key=lambda item: str(item.get("id"))) == sorted(desired, key=lambda item: str(item.get("id"))):
            continue
        new_text = json.dumps(desired, ensure_ascii=False, separators=(",", ":"))
        if len(new_text) > 32768:
            raise ValueError(f"Product_Advantages__c too long on {row['Id']}")
        backup.append({"Id": row["Id"], "Season_Id__c": row["Season_Id__c"],
                       "Inventory_Id__c": row["Inventory_Id__c"], "before": old_text, "after": new_text})
        updates.append({"attributes": {"type": "Inventory__c"}, "Id": row["Id"],
                        "Product_Advantages__c": new_text})
    return updates, backup


def resolve_links(links, parents, inventory):
    parent_ids = {row["Advantage_Key__c"]: row["Id"] for row in parents}
    inventories = {}
    for row in inventory:
        if row.get("Inventory_Id__c") and row.get("Season_Id__c"):
            key = (str(row["Season_Id__c"]), str(row["Inventory_Id__c"]))
            if key in inventories:
                raise ValueError(f"Ambiguous Inventory season/product {key}")
            inventories[key] = row["Id"]
    matched = 0
    for link in links:
        parent_key = link["_parent_key"]
        link["Catalog_Advantage__c"] = parent_ids[parent_key]
        inventory_id = inventories.get((link["Season_Id__c"], link["Product_Id__c"]))
        link["Inventory__c"] = inventory_id
        matched += bool(inventory_id)
    return matched


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--catalog-file", type=Path)
    source.add_argument("--catalog-url", help="Full GET Catalog raw endpoint")
    parser.add_argument("--save-catalog-file", type=Path,
                        help="Save downloaded source bytes for audit (required with --catalog-url)")
    parser.add_argument("--target-org", required=True)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--allow-production", action="store_true")
    parser.add_argument("--clean-legacy", action="store_true",
                        help="Align Inventory__c.Product_Advantages__c with the full catalog snapshot")
    parser.add_argument("--backup-file", type=Path,
                        help="Required with --clean-legacy; saves every before/after value")
    args = parser.parse_args()
    if args.catalog_url and not args.save_catalog_file:
        parser.error("--catalog-url requires --save-catalog-file")
    if args.clean_legacy and not args.backup_file:
        parser.error("--clean-legacy requires --backup-file")
    if args.execute and args.target_org.lower() in ("tfa prod", "prod") and not args.allow_production:
        parser.error("Production write requires --allow-production")
    if args.catalog_url:
        with urllib.request.urlopen(args.catalog_url, timeout=300) as response:
            source_bytes = response.read()
        if args.save_catalog_file.exists():
            parser.error("Catalog save file already exists; choose a new path")
        args.save_catalog_file.parent.mkdir(parents=True, exist_ok=True)
        args.save_catalog_file.write_bytes(source_bytes)
    else:
        source_bytes = args.catalog_file.read_bytes()
    document = json.loads(source_bytes.decode("utf-8-sig"))
    parents, links = parse_catalog(document)
    print(json.dumps({"org": args.target_org, "execute": args.execute,
                      "advantages": len(parents), "links": len(links),
                      "seasons": sorted({r["Season_Id__c"] for r in parents}),
                      "catalog_started": document.get("started"),
                      "catalog_sha256": hashlib.sha256(source_bytes).hexdigest()}))
    if not args.execute:
        return
    if args.clean_legacy:
        inventory_before = query_all("SELECT Id, Inventory_Id__c, Season_Id__c, Product_Advantages__c FROM Inventory__c", args.target_org)
        changes, backup = legacy_updates(parents, links, inventory_before)
        if args.backup_file.exists():
            parser.error("Backup file already exists; choose a new path")
        args.backup_file.parent.mkdir(parents=True, exist_ok=True)
        args.backup_file.write_text(json.dumps(backup, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Legacy JSON changes prepared: {len(changes)}; backup: {args.backup_file}")
    upsert_collection("Catalog_Advantage__c", "Advantage_Key__c", parents, args.target_org)
    sf_parents = query_all("SELECT Id, Advantage_Key__c FROM Catalog_Advantage__c", args.target_org)
    inventory = query_all("SELECT Id, Inventory_Id__c, Season_Id__c FROM Inventory__c", args.target_org)
    matched = resolve_links(links, sf_parents, inventory)
    print(f"Inventory links matched to the same season: {matched}/{len(links)}")
    upsert_collection("Catalog_Advantage_Product__c", "Relationship_Key__c",
                      [{k: v for k, v in link.items() if k != "_parent_key"} for link in links], args.target_org)
    final_parents = query_all("SELECT Id FROM Catalog_Advantage__c", args.target_org)
    final_links = query_all("SELECT Id FROM Catalog_Advantage_Product__c", args.target_org)
    if len(final_parents) < len(parents) or len(final_links) < len(links):
        raise RuntimeError("Post-write counts are below snapshot counts")
    print(json.dumps({"verified_advantages": len(final_parents), "verified_links": len(final_links)}))
    if args.clean_legacy:
        update_collection("Inventory__c", changes, args.target_org)
        current = query_all("SELECT Id, Inventory_Id__c, Season_Id__c, Product_Advantages__c FROM Inventory__c", args.target_org)
        remaining, _ = legacy_updates(parents, links, current)
        if remaining:
            raise RuntimeError(f"Legacy JSON reconciliation incomplete: {len(remaining)} rows")
        print(json.dumps({"legacy_json_rows_cleaned": len(changes), "legacy_remaining": 0}))


if __name__ == "__main__":
    main()
