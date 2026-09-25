"""Read-only Salesforce schema and aggregate profiling for the Tableau explainer.

Uses the existing Salesforce CLI login. No row-level customer data is collected.
"""
import concurrent.futures
import datetime
import json
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / '.local' / 'tableau-production'
OUT.mkdir(parents=True, exist_ok=True)
SF = shutil.which('sf')
ORG = 'TFA Prod'

def cli(*args):
    result = subprocess.run([SF, *args, '--target-org', ORG, '--json'], capture_output=True, text=True, encoding='utf-8', timeout=180)
    payload = json.loads(result.stdout)
    if payload.get('status') != 0:
        raise RuntimeError(payload.get('message', 'Salesforce CLI error'))
    return payload['result']

def save(name, payload):
    (OUT / name).write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding='utf-8')

def describe(name):
    path = OUT / 'describe' / (name + '.json')
    data = cli('sobject', 'describe', '--sobject', name)
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding='utf-8')
    return name, data

def profile(item):
    name, data = item
    fields = [f['name'] for f in data['fields'] if f['type'] == 'reference' and not f['name'] in ['CreatedById', 'LastModifiedById', 'OwnerId']]
    if name.endswith('__c') and not name.startswith('et4ae5__'):
        fields += [f['name'] for f in data['fields'] if f.get('externalId') and f['name'] not in fields]
    fields = fields[:75]
    columns = ['COUNT(Id) total'] + [f'COUNT({f}) f{i}' for i, f in enumerate(fields)]
    soql = 'SELECT ' + ', '.join(columns) + ' FROM ' + name
    try:
        result = cli('data', 'query', '--query', soql)
        row = result['records'][0]
        return name, {'total': row['total'], 'populated': {f: row['f'+str(i)] for i,f in enumerate(fields)}, 'query': soql, 'queriedUtc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    except Exception as exc:
        return name, {'error': str(exc), 'query': soql}

def main():
    org = cli('data', 'query', '--query', 'SELECT Id, Name, IsSandbox FROM Organization')['records'][0]
    custom = cli('sobject', 'list', '--sobject', 'custom')
    standard = ['Account','Contact','Order','OrderItem','Product2','Pricebook2','PricebookEntry','Opportunity','OpportunityLineItem','Campaign','CampaignMember','Contract','Asset','User','RecordType','Lead']
    names = [n for n in custom if n.endswith('__c')] + standard
    save('scope.json', {'verifiedUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'org': org, 'customObjects': custom, 'standardObjects': standard, 'note': 'Read-only describes and aggregate counts. Counts exclude deleted records and reflect the current CLI user.'})
    descriptions = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        for task in concurrent.futures.as_completed({pool.submit(describe,n):n for n in names}):
            try:
                name,data=task.result(); descriptions[name]=data
            except Exception as exc:
                print('Describe failed:', str(exc), flush=True)
    print('Described',len(descriptions),'objects',flush=True)
    profiles = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        for name, data in pool.map(profile, descriptions.items()):
            profiles[name] = data
    save('profiles.json', profiles)
    relationships=[]
    for name,data in sorted(descriptions.items()):
        for field in data['fields']:
            if field['type'] == 'reference':
                relationships.append({'child':name,'field':field['name'],'label':field['label'],'targets':field['referenceTo'],'nullable':field['nillable'],'relationshipName':field.get('relationshipName'),'cascadeDelete':field.get('cascadeDelete'),'relationshipOrder':field.get('relationshipOrder'),'custom':field['custom']})
    save('relationships.json',relationships)
    print(json.dumps({n:p.get('total',p.get('error')) for n,p in sorted(profiles.items())},indent=2),flush=True)

if __name__ == '__main__':
    main()
