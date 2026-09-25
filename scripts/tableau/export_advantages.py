"""Export current SecuTix product advantages as a Tableau-ready relationship table.

Read-only Salesforce query. Exports catalog products and advantage definitions only;
no customer/contact records or raw JSON payloads are written.
"""
import csv
import datetime
import json
import pathlib

from inspect_production import cli

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'outputs' / 'tableau-production'
OUT.mkdir(parents=True, exist_ok=True)
QUERY = 'SELECT Id, Inventory_Id__c, Code__c, Product_Advantages__c FROM Inventory__c'
COLUMNS = ['Inventory_Salesforce_Id','Inventory_Id__c','Product_Code__c','Advantage_Id','Advantage_Code','Advantage_Name_IT','Advantage_Name_EN','Advantage_Target_Type']

result = cli('data', 'query', '--query', QUERY)
if not result.get('done') or len(result['records']) != result['totalSize']:
    raise RuntimeError('Inventory query did not return every row; refusing a partial export.')

rows = []
populated = 0
nonempty = 0
for inventory in result['records']:
    raw = inventory.get('Product_Advantages__c')
    if not raw:
        continue
    populated += 1
    advantages = json.loads(raw)
    if not isinstance(advantages, list):
        raise ValueError('Unexpected product-advantages JSON shape')
    if advantages:
        nonempty += 1
    for advantage in advantages:
        if not isinstance(advantage, dict):
            raise ValueError('Unexpected advantage row shape')
        rows.append({
            'Inventory_Salesforce_Id': inventory['Id'],
            'Inventory_Id__c': inventory['Inventory_Id__c'],
            'Product_Code__c': inventory.get('Code__c'),
            'Advantage_Id': advantage.get('id'),
            'Advantage_Code': advantage.get('code'),
            'Advantage_Name_IT': advantage.get('name_it'),
            'Advantage_Name_EN': advantage.get('name_en'),
            'Advantage_Target_Type': advantage.get('advantageTargetType'),
        })

destination = OUT / 'product-advantages.csv'
def csv_value(value):
    # Make translated names and codes safe when the CSV is also opened in Excel.
    if isinstance(value, str) and value.startswith(('=', '+', '-', '@')):
        return "'" + value
    return value

with destination.open('w', encoding='utf-8-sig', newline='') as stream:
    writer = csv.DictWriter(stream, fieldnames=COLUMNS)
    writer.writeheader()
    writer.writerows({key: csv_value(value) for key, value in row.items()} for row in rows)

print(json.dumps({
    'verifiedUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'inventories': len(result['records']),
    'inventoriesWithJson': populated,
    'inventoriesWithAdvantages': nonempty,
    'productAdvantageLinks': len(rows),
    'distinctAdvantages': len({str(r['Advantage_Id']) for r in rows if r['Advantage_Id'] is not None}),
    'csv': str(destination),
}, ensure_ascii=False))
