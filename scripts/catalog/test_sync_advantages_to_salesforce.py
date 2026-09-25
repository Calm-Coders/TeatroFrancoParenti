import importlib.util
import json
import pathlib
import unittest

PATH = pathlib.Path(__file__).with_name("sync_advantages_to_salesforce.py")
SPEC = importlib.util.spec_from_file_location("advantage_sync", PATH)
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


class AdvantageSyncTests(unittest.TestCase):
    def sample(self):
        return {"order": {"catalogData": {"seasons": [
            {"id": 10, "advantages": [{"id": 20, "code": "A", "mandatoryContact": True,
                "externalName": {"translations": [{"locale": "it", "value": "Ridotto"}]},
                "products": [{"id": 30, "code": "P"}]}]}
        ]}}}

    def test_keys_and_season_safe_link(self):
        parents, links = SYNC.parse_catalog(self.sample())
        self.assertEqual(parents[0]["Advantage_Key__c"], "10|20")
        self.assertEqual(parents[0]["Name_IT__c"], "Ridotto")
        self.assertTrue(parents[0]["Mandatory_Contact__c"])
        self.assertEqual(links[0]["Relationship_Key__c"], "10|20|30")
        matched = SYNC.resolve_links(
            links, [{"Advantage_Key__c": "10|20", "Id": "adv"}],
            [{"Inventory_Id__c": "30", "Season_Id__c": "11", "Id": "wrong"}])
        self.assertEqual(matched, 0)
        self.assertIsNone(links[0]["Inventory__c"])
        self.assertEqual(links[0]["Catalog_Advantage__c"], "adv")

    def test_duplicate_source_pair_is_rejected(self):
        document = self.sample()
        product = document["order"]["catalogData"]["seasons"][0]["advantages"][0]["products"][0]
        document["order"]["catalogData"]["seasons"][0]["advantages"][0]["products"].append(product)
        with self.assertRaisesRegex(ValueError, "Duplicate advantage/product"):
            SYNC.parse_catalog(document)

    def test_legacy_json_removes_stale_and_adds_current(self):
        parents, links = SYNC.parse_catalog(self.sample())
        inventory = [{"Id": "inv", "Inventory_Id__c": "30", "Season_Id__c": "10",
                      "Product_Advantages__c": json.dumps([{"id": 99, "code": "OLD"}])}]
        updates, backup = SYNC.legacy_updates(parents, links, inventory)
        self.assertEqual(len(updates), 1)
        self.assertEqual(json.loads(updates[0]["Product_Advantages__c"])[0]["id"], 20)
        self.assertEqual(json.loads(backup[0]["before"])[0]["id"], 99)


if __name__ == "__main__":
    unittest.main()
