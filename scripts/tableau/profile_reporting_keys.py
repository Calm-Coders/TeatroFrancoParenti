"""Read-only aggregate checks for candidate Tableau relationship keys."""
import concurrent.futures
import datetime
import json
from inspect_production import cli, OUT, save

QUERIES = {
    'performance_key_uniqueness': 'SELECT COUNT(Id) total, COUNT(Performance_Id__c) populated, COUNT_DISTINCT(Performance_Id__c) distinctKeys FROM Performance__c',
    'operation_keys': 'SELECT COUNT(Id) total, COUNT(Operation_Id__c) operationKeys, COUNT(Performance_Id__c) performanceKeys, COUNT(Product_Id__c) productKeys, COUNT(Audience_SubCategory_Id__c) audienceKeys, COUNT(Seat_Category_Id__c) seatKeys FROM Order_Operation_Data__c',
    'movement_keys': 'SELECT COUNT(Id) total, COUNT(Movement_Id__c) movementKeys, COUNT(Seat_Category_Id__c) seatKeys FROM Order_Movement_Data__c',
    'access_keys': 'SELECT COUNT(Id) total, COUNT(Order_Id__c) orderKeys, COUNT(Product_Id__c) productKeys, COUNT(Cultural_Contact_Number__c) contactKeys, COUNT(Ticket_Id__c) ticketKeys FROM Access_Control__c',
    'order_states': 'SELECT Status, Order_State__c, COUNT(Id) rows FROM Order GROUP BY Status, Order_State__c',
    'operation_types': 'SELECT Type__c, Kind__c, COUNT(Id) rows FROM Order_Operation_Data__c GROUP BY Type__c, Kind__c',
    'access_states': 'SELECT Ticket_State__c, COUNT(Id) rows FROM Access_Control__c GROUP BY Ticket_State__c',
    'sale_period_parent_types': 'SELECT Parent_Type__c, COUNT(Id) rows FROM Sale_Period__c GROUP BY Parent_Type__c',
    'performance_prices_seat_ids': 'SELECT COUNT(Id) total, COUNT(Seat_Category_Id__c) sourceSeatKeys FROM Performance_Price__c',
    'account_business_keys': 'SELECT COUNT(Id) total, COUNT(Contact_Number__c) contactKeys FROM Account',
}

def query(item):
    name,soql=item
    try:
        r=cli('data','query','--query',soql)
        return name, {'query':soql,'records':r['records'],'done':r.get('done'), 'totalSize':r.get('totalSize')}
    except Exception as exc:
        return name, {'query':soql,'error':str(exc)}

def candidate(child, field, target, target_field):
    r=cli('data','query','--query',f'SELECT {target_field} FROM {target} WHERE {target_field} != null')
    keys=sorted({str(row[target_field]) for row in r['records']})
    matches=0
    for start in range(0,len(keys),400):
        escaped=["'"+k.replace('\\','\\\\').replace("'","\\'")+"'" for k in keys[start:start+400]]
        q=f'SELECT COUNT(Id) n FROM {child} WHERE {field} IN ('+', '.join(escaped)+')'
        matches+=cli('data','query','--query',q)['records'][0]['n']
    totals=cli('data','query','--query',f'SELECT COUNT(Id) total, COUNT({field}) populated FROM {child}')['records'][0]
    return {'child':child,'field':field,'target':target,'targetField':target_field,'targetRows':len(r['records']),'distinctTargetKeys':len(keys),'matchedSourceRows':matches,'totalSourceRows':totals['total'],'populatedSourceRows':totals['populated'],'targetQueryComplete':r.get('done'), 'method':'Count child rows whose nonblank text key is in the distinct current target-key set; 400-key disjoint batches. Case-sensitive uniqueness not separately tested.'}

def main():
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        metrics=dict(pool.map(query, QUERIES.items()))
    save('reporting-metrics.json',metrics)
    specs=[
        ('Order_Operation_Data__c','Product_Id__c','Inventory__c','Inventory_Id__c'),
        ('Order_Operation_Data__c','Performance_Id__c','Performance__c','Performance_Id__c'),
        ('Order_Operation_Data__c','Audience_SubCategory_Id__c','Audience_Sub_Category__c','Audience_Subcategory_Id__c'),
        ('Order_Operation_Data__c','Seat_Category_Id__c','Seat_Category__c','Seat_Category_Id__c'),
        ('Order_Movement_Data__c','Seat_Category_Id__c','Seat_Category__c','Seat_Category_Id__c'),
        ('Sale_Period_Seat_Category__c','Seat_Category_Id__c','Seat_Category__c','Seat_Category_Id__c'),
        ('Access_Control__c','Product_Id__c','Inventory__c','Inventory_Id__c'),
    ]
    results=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for future in concurrent.futures.as_completed([pool.submit(candidate,*s) for s in specs]):
            try: results.append(future.result())
            except Exception as exc: results.append({'error':str(exc)})
    save('candidate-profiles.json', {'verifiedUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'candidates':results})
    print(json.dumps({'metrics':metrics,'candidates':results},indent=2),flush=True)

if __name__=='__main__':main()
