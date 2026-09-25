"""Build the evidence-backed Tableau object model from read-only inspection files."""
import csv
import datetime
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
DATA = ROOT / '.local' / 'tableau-production'
OUT = ROOT / 'outputs' / 'tableau-production'
OUT.mkdir(parents=True, exist_ok=True)

def read(name):
    return json.loads((DATA / name).read_text(encoding='utf-8'))

scope = read('scope.json')
profiles = read('profiles.json')
describes = {p.stem: json.loads(p.read_text(encoding='utf-8')) for p in (DATA / 'describe').glob('*.json')}
candidate_profiles = read('candidate-profiles.json')

# domain, grain, important measures, business notes
BUSINESS = {
 'Account': ('Customers', 'One current customer or organization account; SecuTix contacts are loaded here.', [], ['Contact_Number__c is the unique external customer key. Account.ParentId relates an individual to an organization where supplied.', 'Use separate purchaser and movement-holder roles. Monthly anonymous fallback accounts exist; distinct Account counts are not automatically identified-customer counts.']),
 'Order': ('Sales', 'One current order header, keyed by Order_Id__c or Order_Secret_Id__c.', ['Sale_Amount__c','Pre_Sale_Amount__c','Reservation_Amount__c','Option_Amount__c','Waiting_Account_Balance_Amount__c'], ['Aggregate header amounts at Order grain. Use Order_State__c for business state; all profiled standard Status values are Draft.', 'Product_Id__c is only the first non-CHARGES product. Use operations for the complete basket.', 'Creation_Date_Time__c and Reference_Date__c are text: parse and validate timezone before using a date dimension.']),
 'Order_Operation_Data__c': ('Sales', 'One operation from the latest order payload; operations include admissions, composition, charges, refunds and reservations.', ['Quantity__c','Total_Amount__c','Without_Vat_Total_Amount__c','Unit_Price__c','Base_Price__c'], ['Order__c is the header lookup; Inventory__c is the current product lookup. Parent_Operation__c expresses composition/parentage.', 'Performance__c, Audience_SubCategory__c and Seat_Category__c are text labels, not lookups. Candidate text-ID relationships are listed separately.', 'Operation_Id__c is not metadata-unique. Validate Order business key + Operation_Id__c before using a durable warehouse key.', 'Recreated on order update: Salesforce Id is a current row key, not a stable historical business key. Do not sum Unit_Price__c as revenue; define filters and package/charge handling before summing totals.']),
 'Order_Movement_Data__c': ('Sales', 'One seat/movement from the latest order payload; optionally associated with a holder account.', [], ['Order_Operation_Data__c identifies the exact operation. Order__c supplies a direct header link. Account__c is the holder role, not necessarily the buyer.', 'Avoid two routes from Movement to Order in the same Tableau relationship tree: use Movement → Operation → Order, or a deliberate alternative.', 'Movement_Id__c has no uniqueness constraint; validate order + movement business key. Salesforce Id changes when order children are rebuilt.', 'Seat_Category__c is text; a candidate Seat_Category_Id__c join is only partially covered by the current catalog.']),
 'Access_Control__c': ('Access', 'Current snapshot: one record per populated unique Barcode__c; upserted state, not an immutable scan-event log.', ['Group_Size__c','Price__c'], ['Order__c and Inventory__c are real lookups but are almost entirely empty in this snapshot.', 'All current rows have a barcode. The schema permits blank barcodes, and those payloads can insert additional records.', 'COUNT of rows is a barcode-record count, not verified attendance or scan count. Group_Size__c can represent multiple people.', 'Price__c stores the incoming value unchanged. Its unit is not established as equal to order currency values.', 'No native Account, Performance or Movement lookup exists. Do not join barcode to Movement_Id__c or assume Ticket_Id__c is a movement key.']),
 'Inventory__c': ('Catalog', 'One current catalog product per unique Inventory_Id__c.', [], ['This is the ticketing product dimension. Standard Salesforce Product2 and OrderItem have zero rows in this snapshot.', 'Contains product family, season and translated descriptions. Some nested source arrays remain JSON; typed child objects provide usable relations.', 'Current product state can replace earlier season metadata. Preserve order snapshots or separate history for historical product/season attributes.']),
 'Inventory_Event__c': ('Catalog', 'One event-detail row linked to a catalog inventory product.', [], ['Follow Inventory__c to product, and incoming Performance__c.Inventory_Event__c for scheduled performances.', 'The source models this as a subtype, but metadata does not enforce a one-to-one inventory/event relationship. Use N:1 child-to-parent unless separately proven.']),
 'Performance__c': ('Catalog', 'One current scheduled performance under an inventory event.', ['Duration__c'], ['Start__c is a typed datetime. Venue_Location__c is the real venue lookup.', 'Performance_Id__c is text with no uniqueness constraint; all 3,414 current values were present and distinct in the key check.', 'Catalog refresh can delete and recreate these rows and dependent children. Use a full refresh or deletion-aware extraction.']),
 'Venue_Location__c': ('Catalog', 'One reusable site/space location, identified by Location_Key__c.', [], ['Site and space names/codes are descriptive attributes. Follow Performance__c.Venue_Location__c; do not join on venue labels.']),
 'Performance_Seat_Category__c': ('Pricing', 'One performance-to-seat-category bridge row.', [], ['The bridge expresses which seat categories are associated with a performance. Its unique Relationship_Key__c is the stored compound relationship key.', 'Multiple categories per performance multiply rows if flattened into the performance or price fact.']),
 'Seat_Category__c': ('Pricing', 'One catalog seat category with unique Seat_Category_Id__c and Category_Key__c.', [], ['Reusable dimension for performance/category bridges. Operational text IDs only partially match this current catalog.']),
 'Audience_Sub_Category__c': ('Pricing', 'One catalog audience/tariff subcategory with unique Audience_Subcategory_Id__c.', [], ['Used by prices, sale eligibility and forced package-line audience. Audience_Key__c is also unique.', 'The spelling differs from Order_Operation_Data__c.Audience_SubCategory_Id__c; use exact API names shown in the candidate join.']),
 'Performance_Price__c': ('Pricing', 'One configured performance price occurrence with optional audience and seat category.', ['Amount__c'], ['Price_Key__c is unique; source duplicates can receive occurrence suffixes. Do not assume Performance + Audience alone is a unique key.', 'Configured catalog price is not realized sale revenue. All 2,936 rows have audience and performance links; none has Seat_Category__c or Seat_Category_Id__c populated.', 'Relating prices to all performance seat categories would not recover a proven seat-specific price mapping.']),
 'Performance_Price_Charge__c': ('Pricing', 'One charge occurrence under a configured performance price.', ['Amount__c'], ['Schema exists but there are zero current rows. Keep this branch available only if charge data is subsequently populated.']),
 'Charge_Component__c': ('Pricing', 'One reusable charge definition identified by Charge_Id__c / Charge_Key__c.', [], ['Schema exists but the object has zero current rows. Do not equate catalog charge definitions with order CHARGES operations.']),
 'Sale_Period__c': ('Availability', 'One selling window for an inventory, performance or membership-item price.', [], ['Parent_Type__c determines the parent role. Current rows: 14 Inventory windows and 462 Performance windows; zero Membership Item Price windows.', 'Start__c / End__c, sale/reservation/quotation flags and Sales_Channel__c describe selling eligibility, not purchases.']),
 'Sale_Period_Audience__c': ('Availability', 'One audience restriction under a sale period.', [], ['Links a period to Audience_Sub_Category__c. Multiple audiences and seat restrictions are separate one-to-many branches; joining both physically creates combinations.']),
 'Sale_Period_Seat_Category__c': ('Availability', 'One source seat-category restriction under a sale period.', [], ['Sale_Period__c is a lookup. Seat_Category_Id__c is text, with no native lookup to Seat_Category__c. Candidate text join has 48 unmatched rows in this snapshot.']),
 'Sales_Channel__c': ('Availability', 'One catalog selling channel keyed by Channel_Key__c.', [], ['Order.Sales_Channel_Code__c is an attribute, not a lookup to this object. A code join requires uniqueness and coverage checks.', 'One catalog channel exists now; do not assume it covers all historical order channels.']),
 'Membership__c': ('Composition', 'One membership product-detail row linked to inventory.', [], ['Catalog offer definition, not a customer membership purchase or entitlement record.']),
 'Membership_Item__c': ('Composition', 'One membership item/option under a membership product.', ['Donation_Amount__c','Voucher_Amount__c'], ['Relationship_Key__c is unique. Prices and eligibility periods are further child branches; their current price branch is empty.']),
 'Membership_Item_Price__c': ('Composition', 'One configured price occurrence for a membership item and audience.', ['Amount__c'], ['Zero current rows. Catalog monetary fields are normalized by the integration; do not divide them again.']),
 'Pack__c': ('Composition', 'One package product-detail row linked to inventory.', [], ['A catalog package definition. Use Order operations to analyze actual package purchases.']),
 'Package_Line__c': ('Composition', 'One source package line within a pack, identified by Relationship_Key__c.', ['Quantity__c'], ['Pack__c is its parent. Target_Inventory__c identifies the contained product; Forced_Audience_Sub_Category__c optionally constrains audience.', 'All 112 target-inventory links are populated; 101 have forced audience, and the remaining 11 may be intentionally unrestricted.', 'Parent_Package_Line__c is a self-reference, currently unpopulated. Target product requires a separate Inventory role from the pack product.']),
 'Season_Ticket__c': ('Composition', 'One season-ticket product-detail row linked to inventory.', [], ['A catalog composition definition, not the fact of a customer owning a season ticket.']),
 'Season_Ticket_Line__c': ('Composition', 'One season-ticket composition line under a season-ticket product.', [], ['Target_Inventory__c identifies its component product; Subject__c optionally groups a line under a subject.', 'All 612 lines have target inventory; none currently has Subject__c.']),
 'Season_Ticket_Subject__c': ('Composition', 'One subject/group within a season-ticket definition.', [], ['Zero current rows. Subject membership is represented by Season_Ticket_Line__c.Subject__c when populated.']),
 'Cross_Sell_Product_Link__c': ('Composition', 'One directed source-product → recommended-target-product relationship.', [], ['Both Source_Inventory__c and Target_Inventory__c point to Inventory. Use separate source/target roles and do not treat recommendation links as transactions.']),
}

BUSINESS['Account'][3].insert(1, 'Customer agevolazioni arrive as advantages[] and hasAdvantages in the SecuTix contact webhook. Account.Advantages__c stores the raw JSON and Account.Has_Advantages__c stores the flag; 23,013 Accounts currently have the flag true. This describes customer eligibility, not a proven purchased discount.')
BUSINESS['Inventory__c'][3].insert(1, 'Product agevolazioni arrive as advantages[] in the SecuTix catalog resolve response and are saved in Product_Advantages__c as JSON text. The current export has 141 product-to-advantage links across 71 products and 39 distinct advantage IDs. Use product-advantages.csv as a Tableau bridge: Inventory_Salesforce_Id → Inventory__c.Id.')
BUSINESS['Inventory__c'][3].insert(2, 'There is no Advantage__c business object or native lookup from Inventory to an advantage. Customer Account.Advantages__c is a separate contact payload, so no product-to-customer advantage relationship is asserted.')

SUPPORT = {'Integration_Log__c','Catalog_Enrichment_Setting__c','In_App_Checklist_Settings__c','User','RecordType'}
CUSTOMER_OPTIONAL = {'Contact','Lead','Campaign','CampaignMember','Opportunity','OpportunityLineItem','Contract','Asset','OrderItem','Product2','Pricebook2','PricebookEntry'}
optional_notes = {
 'Contact': 'Only 3 current rows; the SecuTix customer integration writes Account. Do not use this as the ticketing customer master.',
 'Opportunity': '50 current CRM opportunities; Order.OpportunityId has zero populated links. Treat pipeline as its own subject area.',
 'Campaign': '3 current campaigns; campaign attribution to ticketing orders is not established by the audited links.',
 'CampaignMember': '15 current membership rows, linking Lead or Contact. No audited automatic attribution to ticket purchasers.',
 'OrderItem': 'Zero rows. Ticketing order lines are Order_Operation_Data__c, not standard OrderItem.',
 'Product2': 'Zero rows. Ticketing products are Inventory__c.',
 'Integration_Log__c': 'Operational request/response logging, not a financial fact. Large payload bodies are not needed in the core Tableau model.',
 'Catalog_Enrichment_Setting__c': 'Integration configuration/custom setting; exclude from business measures.',
 'In_App_Checklist_Settings__c': 'Application configuration/custom setting; exclude from business measures.',
 'User': 'Optional owner/creator/modifier dimension. Do not conflate Salesforce users with customers.',
 'RecordType': 'Optional labels for object record types; not a business transaction.'
}

objects=[]
for name,d in sorted(describes.items()):
    if name in BUSINESS:
        domain,grain,measures,notes=BUSINESS[name];tier='core'
    elif name in SUPPORT:
        domain,grain,measures,notes,tier='Operations', 'One administrative or support record.', [], [optional_notes.get(name,'Optional administrative context.')], 'support'
    elif name.startswith('et4ae5__'):
        domain,grain,measures,notes,tier='Marketing package', 'One managed-package record; business grain needs package-specific validation.', [], ['Optional Marketing Cloud package. Schema and counts are inventoried; no ticketing attribution model has been established.'], 'optional'
    else:
        domain,grain,measures,notes,tier='CRM extensions', 'One '+d['label']+' record at native Salesforce object grain.', [], [optional_notes.get(name,'Optional standard CRM branch; include only for a defined reporting use case.')], 'optional'
    fields=[{'name':f['name'],'label':f['label'],'type':f['type'],'referenceTo':f['referenceTo'],'nullable':f['nillable'],'unique':f['unique'],'externalId':f['externalId']} for f in d['fields']]
    keys=[{'name':'Id','unique':True,'externalId':False}]+[{'name':f['name'],'unique':f['unique'],'externalId':f['externalId']} for f in d['fields'] if f['externalId']]
    if name in ['Order_Operation_Data__c','Order_Movement_Data__c','Performance__c']:
        keys.append({'name':{'Order_Operation_Data__c':'Operation_Id__c','Order_Movement_Data__c':'Movement_Id__c','Performance__c':'Performance_Id__c'}[name],'unique':False,'externalId':False})
    objects.append(dict(name=name,label=d['label'],domain=domain,tier=tier,grain=grain,count=profiles[name].get('total'),keys=keys,measures=measures,notes=notes,fields=fields,queryError=profiles[name].get('error')))
by_name={o['name']:o for o in objects}
relations=[]
for child,d in sorted(describes.items()):
    for f in d['fields']:
        if f['type']!='reference':continue
        audit=f['name'] in ['CreatedById','LastModifiedById','OwnerId','LastViewedById']
        p=profiles[child]
        for target in f['referenceTo']:
            kind='Polymorphic reference' if len(f['referenceTo'])>1 else ('Master-detail' if f.get('relationshipOrder') is not None else ('Lookup' if f['custom'] else 'Standard reference'))
            notes=[]
            if audit:notes.append('Administrative relationship; optional for business reporting. Population was not profiled.')
            if len(f['referenceTo'])>1:notes.append('One field can reference one of '+', '.join(f['referenceTo'])+'. Coverage is field-level across all targets; isolate the target type before joining.')
            if target not in describes:notes.append('Target is outside the described Tableau scope; target rows were not profiled.')
            if not f['nillable']:notes.append('Child reference is required by schema. This does not mean every parent has a child.')
            if p.get('total')==0:notes.append('Child table is currently empty; this is an available schema relationship.')
            if child=='Order_Movement_Data__c' and f['name']=='Account__c':notes.append('Movement holder role; may differ from the order purchaser.')
            if child=='Order' and f['name']=='AccountId':notes.append('Order purchaser role, including anonymous fallback accounts.')
            if child=='Sale_Period__c' and f['name'] in ['Inventory__c','Performance__c','Membership_Item_Price__c']:notes.append('Alternative parent role determined by Parent_Type__c; do not require all three parent fields.')
            relations.append(dict(id=f'{child}.{f["name"]}.{target}',child=child,field=f['name'],target=target,nullable=f['nillable'],populated=p.get('populated',{}).get(f['name']),total=p.get('total'),kind=kind,relationshipName=f.get('relationshipName'),notes=' '.join(notes),administrative=audit,tier='core' if child in BUSINESS and target in BUSINESS and not audit else 'support',cardinality='N:1 per target type' if len(f['referenceTo'])>1 else 'N:1',targetField='Id'))

candidates=[]
for c in candidate_profiles['candidates']:
    if 'error' in c:continue
    status='Validated current keys; partial coverage'
    explanation=f"Text-key candidate, not a Salesforce lookup. {c['matchedSourceRows']:,} of {c['totalSourceRows']:,} child rows match the current target; {c['populatedSourceRows']:,} child rows have a source key. Target: {c['distinctTargetKeys']:,} distinct nonblank keys across {c['targetRows']:,} rows."
    if c['target']=='Performance__c':explanation+=' Current key uniqueness is observed, not enforced. Recheck each refresh and preserve unmatched historical operations.'
    if c['child']=='Order_Operation_Data__c' and c['field']=='Product_Id__c':explanation+=' Target Inventory_Id__c is metadata-unique. This text-key mapping covers more current rows than the native lookup; use one deliberate product relationship, not both paths to the same Inventory table.'
    if c['matchedSourceRows']==0:status='Blocked: no current matches'
    candidates.append({**c,'status':status,'reason':explanation,'evidence':'.local/tableau-production/candidate-profiles.json'})
candidates.extend([
 {'child':'Order','field':'Sales_Channel_Code__c','target':'Sales_Channel__c','targetField':'Code__c','status':'Proposed; not profiled','reason':'No native lookup. Code__c is not unique by metadata. Validate uniqueness, scope and historical coverage; retain order channel attributes when the catalog lacks channels.'},
 {'child':'Access_Control__c','field':'Order_Id__c','target':'Order','targetField':'Order_Id__c','status':'Incomplete source; not matched independently','reason':'Only 5 of 8,503 access rows have Order_Id__c. Prefer the existing Order__c lookup when available (1 populated); direct text-key coverage was not independently measured.'},
 {'child':'Access_Control__c','field':'Cultural_Contact_Number__c','target':'Account','targetField':'Contact_Number__c','status':'Proposed; identity role unverified','reason':'Only 4 of 8,503 rows have a cultural contact number. Confirm its business role and matching coverage before treating it as a buyer or ticket-holder relationship.'},
])

def source(title,path=None,url=None,detail=''):
    return {k:v for k,v in dict(title=title,path=path,url=url,detail=detail).items() if v}

sources=[
 source('Product advantage bridge export',path='outputs/tableau-production/product-advantages.csv',detail='Read-only 2026-09-25 extract from Inventory__c.Product_Advantages__c. One row per product × advantage, with product IDs, advantage ID/code, translated names and target type; no customer data.'),
 source('Live Salesforce production schema',path='.local/tableau-production/describe/',detail='64 REST sObject describes through the existing TFA Prod CLI session. Organization.IsSandbox=false; fields, references, nullability and unique/external-ID flags verified.'),
 source('Production row counts and lookup population',path='.local/tableau-production/profiles.json',detail='Read-only COUNT(Id) and COUNT(reference field) per object. Nondeleted rows visible to the CLI user. A populated foreign key is not an independently tested Tableau extract match.'),
 source('Candidate key coverage and uniqueness',path='.local/tableau-production/candidate-profiles.json',detail='Target text keys and aggregate child counts only; no customer record values are included in the artifact.'),
 source('State, key and field availability checks',path='.local/tableau-production/reporting-metrics.json',detail='Read-only grouped states/types and aggregate completeness checks. Collection is not a transactionally consistent snapshot; production changes between queries.'),
 source('Deployed Apex verification',path='.local/tableau-production/code-verification.json',detail='Production integration code checked against repository implementations; the copied code stays local.'),
 source('Catalog integration and production promotion',path='docs/local-catalog-salesforce-sync.md',detail='Production promotion 2026-08-27; typed catalog relationships, normalization and refresh behavior. Earlier UAT counts are not used as current production counts.'),
 source('Tableau data model',url='https://help.tableau.com/current/pro/desktop/en-us/datasource_datamodel.htm',detail='Logical relationships retain native table grain; physical joins combine rows.'),
 source('Cardinality and referential integrity',url='https://help.tableau.com/current/pro/desktop/en-us/cardinality_and_ri.htm',detail='Default to conservative match settings; do not declare complete matching without validating actual extracts.'),
 source('Salesforce connector',url='https://help.tableau.com/current/pro/desktop/en-us/examples_salesforce.htm',detail='Custom objects; extracts only; connector and refresh restrictions.'),
 source('Relate your data',url='https://help.tableau.com/current/pro/desktop/en-us/relate_tables.htm',detail='Use individual objects instead of prejoined Standard Connection templates when building relationships.'),
 source('Build a multi-fact model',url='https://help.tableau.com/current/pro/desktop/en-us/datasource_mfr_build.htm',detail='Avoid cycles, repeated downstream paths and unsupported nested shared tables.'),
 source('When to use multi-fact relationships',url='https://help.tableau.com/current/pro/desktop/en-us/datasource_mfr_when_to_use.htm',detail='Multi-base models require Tableau 2024.2 or later; prefer a single base when sufficient.'),
 source('Multi-fact analysis behavior',url='https://help.tableau.com/current/pro/desktop/en-us/datasource_mfr_multiple_base_tables.htm',detail='Shared dimensions must participate in the view to stitch facts; filter-only fields are insufficient.'),
]

insights=[
 {'title':'Dove si prendono le agevolazioni', 'body':'There are two SecuTix sources. Product agevolazioni are in the catalog resolve response advantages[] and saved as Inventory__c.Product_Advantages__c JSON. The exported product-advantages.csv has 141 product–advantage links across 71 products and 39 distinct advantage IDs. Customer agevolazioni come from the contact webhook: Account.Advantages__c stores its advantages[] JSON, and Account.Has_Advantages__c stores its hasAdvantages flag (23,013 true). No native Advantage__c object or customer-to-product advantage join exists. For Tableau, relate the product bridge to Inventory__c.Id and treat Account eligibility separately.', 'evidence':['Deployed CatalogEnrichmentService','Deployed ContactRestResource','product-advantages.csv']},
 {'title':'Start with the real sales chain', 'body':'Account ← Order ← Order_Operation_Data__c ← Order_Movement_Data__c is the central path. All profiled orders have AccountId, and every operation and movement has its parent links. Inventory__c is the catalog dimension; Product2 and OrderItem are empty.', 'evidence':['profiles.json','Production sObject describes']},
 {'title':'Product matching can improve; access links remain sparse', 'body':'324,527 / 934,482 operations have the native Inventory__c lookup (34.7%). The separately checked Product_Id__c → Inventory_Id__c text-key candidate matches 569,549 / 934,490 operations (60.9%), so native lookup population understates possible current product matching. Access_Control__c has only 1 / 8,503 Order__c links and 0 / 8,503 Inventory__c links. Preserve unmatched rows explicitly.', 'evidence':['profiles.json','candidate-profiles.json']},
 {'title':'A useful performance relationship exists only as a text-key candidate', 'body':'Operation.Performance_Id__c can match Performance.Performance_Id__c: 509,986 of 934,484 operations match the current catalog, from 541,482 nonblank source keys. All 3,414 target keys are distinct now, but uniqueness is not enforced. Operation.Performance__c itself is a label.', 'evidence':['candidate-profiles.json','reporting-metrics.json']},
 {'title':'Price-by-seat analysis is currently incomplete', 'body':'All 2,936 performance prices link to performance and audience, but none has Seat_Category__c or its source Seat_Category_Id__c. Separately, 1,374 performance-to-seat-category bridge rows exist. Those bridges do not prove which price belongs to which seat category.', 'evidence':['profiles.json','reporting-metrics.json']},
 {'title':'Keep each measure at its native row grain', 'body':'An illustrative order with 2 operations and 3 independent access rows can become 6 rows when physically joined on Order. A €100 header would then sum to €600. Relate tables at their own grain or aggregate each branch first. COUNTD prevents duplicated IDs, but does not repair duplicated monetary sums. Relationships also do not allocate a header amount across products or an operation amount across seats: use a measure at the reporting grain or define an allocation rule.', 'evidence':['Tableau data model','Cardinality and referential integrity']},
 {'title':'Plan refreshes around delete-and-recreate integrations', 'body':'Order updates rebuild operations and movements; catalog updates can rebuild performances and children. Their Salesforce Ids may change. Start with full extract refreshes or a deletion-aware staging process; append-only incremental loads can retain stale rows and duplicate totals.', 'evidence':['Deployed OrderRestResource','Deployed InventoryRestResource']},
 {'title':'Define sales, refunds and package counting before KPI creation', 'body':'The live operation types include SALE, PRE_SALE, RESERVATION, ABANDON, refund and cancellation variants; kinds include SINGLE_ENTRY, CHARGES and composition. Standard Order.Status is Draft throughout. Agree Order_State__c, Type__c and Kind__c filters and avoid counting both package parents and components. No net-revenue or attendance formula is asserted here.', 'evidence':['reporting-metrics.json','Deployed OrderRestResource']},
 {'title':'Amount scales differ by integration', 'body':'Deployed order/operation code normalizes incoming money by 1,000. For numeric/unformatted source amounts, performance-price code uses 1,000 and membership code uses 100; their helpers preserve already formatted decimal strings. These stored amounts must not be divided again. Access_Control.Price__c stores input unchanged, so reconcile its unit before comparing it with sales amounts. Catalog Amount__c describes configured price, not realized revenue.', 'evidence':['Deployed integration classes','code-verification.json']},
 {'title':'Use conservative Tableau relationship settings', 'body':'For a single-target Salesforce foreign key → parent Id, the structural child-to-parent cardinality is Many-to-one; no reverse one-to-one claim is made. Use Some records match unless the actual extracted rows prove otherwise. For unvalidated text joins, leave Many-to-many / Some records match until uniqueness and coverage are checked. Native schema constraints do not guarantee matching after extract filters or permissions.', 'evidence':['Cardinality and referential integrity']},
 {'title':'Prepare the extract deliberately', 'body':'Use individual Salesforce objects under Table, then create logical relationships. The native Salesforce connector is extract-only; prejoined Standard Connections limit modeling flexibility. Tableau documents that calculated fields and long text over 4,096 characters are excluded from extracts: test required formulas and use typed child objects rather than raw JSON. Custom SQL and cross-database Salesforce models also have incremental-refresh restrictions.', 'evidence':['Salesforce connector','Relate your data']},
 {'title':'Separate the full source graph from Tableau subject areas', 'body':'The source has loops: Movement connects directly and through Operation to Order; product composition returns to Inventory; price and category branches share Performance. Tableau cannot reproduce every path in one logical tree. Select one path per subject area, or use separately named purchaser/holder, source/target-product and other role copies. Multi-fact modeling needs a compatible Tableau version and carefully chosen shared dimensions.', 'evidence':['Build a multi-fact model','When to use multi-fact relationships','Multi-fact analysis behavior']},
 {'title':'What still needs an implementation decision', 'body':'Dashboard/KPI definitions, Tableau version, native Salesforce versus warehouse route, refresh frequency, timezone, refund sign conventions and historical retention remain unspecified. No Tableau workbook or data-source deployment is included. The object/relationship inventory covers the TFP custom model plus identified CRM and package extensions; it is not a complete inventory of every Salesforce system object.', 'evidence':['Scope of this artifact']},
]

models=[
 {'title':'01 · Order and customer reporting','base':'Order','objects':['Order','Account'], 'body':'Use Order.AccountId → Account.Id as purchaser. Aggregate Sale_Amount__c and other header amounts once per order. Count distinct Order.Id for current orders; distinguish identified customers from fallback accounts.'},
 {'title':'02 · Product and performance sales','base':'Order_Operation_Data__c','objects':['Order_Operation_Data__c','Order','Account','Inventory__c','Performance__c','Audience_Sub_Category__c','Seat_Category__c'], 'body':'Use the operation → Order → purchaser path. For Inventory choose the native lookup or the more complete validated Product_Id__c → Inventory_Id__c candidate, then preserve unmatched products. Add candidate performance/audience/seat joins only with validated keys and unmatched buckets. If Performance is linked directly by text key, avoid a second path back to the same Inventory node through Event. Sum operation amounts only after defining state, type, kind, refunds and package rules.'},
 {'title':'03 · Seat movements and holders','base':'Order_Movement_Data__c','objects':['Order_Movement_Data__c','Order_Operation_Data__c','Order','Account'], 'body':'Use Movement → Operation → Order for the sales path. Add a separate Account role for Movement.Account__c (holder) and Order.AccountId (purchaser). Native movement counts are not necessarily admissions or attendance.'},
 {'title':'04 · Catalog and configured prices','base':'Performance_Price__c','objects':['Performance_Price__c','Performance__c','Inventory_Event__c','Inventory__c','Venue_Location__c','Audience_Sub_Category__c','Seat_Category__c','Performance_Price_Charge__c','Charge_Component__c'], 'body':'Use Price → Performance → Event → Inventory and optional Venue/Audience. Price.Seat_Category__c is empty today; do not infer a price-to-seat join from the separate Performance_Seat_Category bridge. Charge branches are schema-only until populated.'},
 {'title':'05 · Selling windows and restrictions','base':'Sale_Period__c','objects':['Sale_Period__c','Sales_Channel__c','Sale_Period_Audience__c','Sale_Period_Seat_Category__c','Audience_Sub_Category__c','Performance__c','Inventory__c','Membership_Item_Price__c'], 'body':'Model one parent role at a time using Parent_Type__c. Audience and seat restrictions are independent children. Keep them as separate logical branches or preaggregate restrictions; do not flatten their Cartesian combinations.'},
 {'title':'06 · Packs, subscriptions and memberships','base':'Package_Line__c / Season_Ticket_Line__c / Membership_Item__c','objects':['Pack__c','Package_Line__c','Season_Ticket__c','Season_Ticket_Line__c','Season_Ticket_Subject__c','Membership__c','Membership_Item__c','Membership_Item_Price__c','Cross_Sell_Product_Link__c','Inventory__c'], 'body':'Use separate subject areas for each composition fact. Treat parent product and target component product as separate Inventory roles. These rows describe offers, eligibility and recommendations, not customer purchases or entitlements.'},
 {'title':'07 · Access-control data quality','base':'Access_Control__c','objects':['Access_Control__c','Order','Inventory__c'], 'body':'Begin with completeness/state reporting at barcode grain. Only one order lookup and no inventory lookups are populated; 8,498 of 8,503 rows lack Ticket_State__c. Attendance and ticket-to-sales reconciliation need additional source coverage and defined event semantics.'},
 {'title':'08 · Optional CRM / marketing','base':'Opportunity / CampaignMember','objects':['Opportunity','Account','Campaign','CampaignMember','Contact','Lead'], 'body':'Keep pipeline and campaign reporting separate until ticketing attribution keys are established. The 50 opportunities, 3 campaigns and 15 campaign memberships are small optional branches; orders currently have no OpportunityId link. Marketing-package schema is inventoried in the object explorer.'},
]

excluded=[{'name':n,'count':None,'reason':'Platform event or historical trending object; excluded from business-table profiling.'} for n in scope['customObjects'] if not n.endswith('__c')]
excluded.append({'name':'Integration_Configuration__c','count':None,'reason':'Present in local metadata but absent from the production custom-object list. Not presented as a production relationship.'})
external_targets=sorted({r['target'] for r in relations if r['target'] not in describes})
excluded.extend({'name':n,'count':None,'reason':'Referenced system/optional target outside the 64 described objects; schema relationship shown, target count not audited.'} for n in external_targets)

model={
 'scope':{'verifiedUtc':scope['verifiedUtc'],'collectionEndUtc':candidate_profiles['verifiedUtc'],'orgName':scope['org']['Name'],'isSandbox':scope['org']['IsSandbox'],'coreObjectCount':len(BUSINESS),'description':'Read-only production audit of 28 TFP business objects, plus 36 administrative, CRM and Marketing Cloud extension objects. Every reference field on those 64 objects is inventoried, including administrative and polymorphic references. Counts were collected over several minutes, exclude deleted records, reflect the CLI user and may differ slightly between queries. Match percentages measure source population or stated text-key matching, not automatic Tableau readiness.','designSource':'Existing TFP integration explorer palette and system typography (docs/integration-explorer.html).'},
 'objects':objects,'relations':relations,'candidates':candidates,'insights':insights,'models':models,'sources':sources,'excluded':excluded,
}
assert model['scope']['coreObjectCount']==len([o for o in objects if o['tier']=='core'])
model['scope']['description']=model['scope']['description'].replace('28 TFP',str(len(BUSINESS))+' TFP').replace('36 administrative',str(len(objects)-len(BUSINESS))+' administrative')
(DATA/'model.json').write_text(json.dumps(model,indent=2,ensure_ascii=False),encoding='utf-8')
(OUT/'model.json').write_text(json.dumps(model,indent=2,ensure_ascii=False),encoding='utf-8')

for name,rows,columns in [
 ('relationships.csv',relations,['child','field','target','targetField','cardinality','kind','nullable','populated','total','tier','administrative','notes']),
 ('objects.csv',objects,['name','label','domain','tier','count','grain']),
 ('candidate-joins.csv',candidates,['child','field','target','targetField','status','reason']),
]:
    with (OUT/name).open('w',newline='',encoding='utf-8-sig') as f:
        writer=csv.DictWriter(f,fieldnames=columns,extrasaction='ignore');writer.writeheader();writer.writerows(rows)

md=['# TFP production relationships for Tableau','',f"Production: **{scope['org']['Name']}** · Read-only audit started {scope['verifiedUtc']} · Key checks ended {candidate_profiles['verifiedUtc']}",'',model['scope']['description'],'','## Findings','']
for item in insights:md.extend(['### '+item['title'],'',item['body'],'','Evidence: '+', '.join(item['evidence']), ''])
md+=['## Recommended subject areas','']
for m in models:md.extend(['### '+m['title'],'','Base: '+m['base'],'',m['body'],''])
md+=['## Core objects','']
for o in objects:
    if o['tier']!='core':continue
    md+=['### '+o['name'],'',f"{o['domain']} · {o['count']:,} rows",'',o['grain'],'']
    md+=['- '+n for n in o['notes']]+['']
    outgoing=[r for r in relations if r['child']==o['name'] and not r['administrative']]
    for r in outgoing:
        pop='Not profiled' if r['populated'] is None else f"{r['populated']:,}/{r['total']:,} populated"
        md.append(f"- `{r['child']}.{r['field']} → {r['target']}.Id` · {r['kind']} · {r['cardinality']} · {'nullable' if r['nullable'] else 'required'} · {pop}")
    md+=['']
md+=['## Candidate text-key joins','']
for c in candidates:md.extend([f"- `{c['child']}.{c['field']} → {c['target']}.{c['targetField']}` — **{c['status']}**. {c['reason']}"])
md+=['','## Sources','']
for s in sources:md.append('- '+('['+s['title']+']('+s['url']+')' if s.get('url') else s['title']+' — `'+s.get('path','')+'`')+'. '+s['detail'])
md+=['','The HTML explorer and accompanying CSVs contain all optional/support objects and every reference on the 64 profiled objects. No production data or metadata was modified.','']
(OUT/'tableau-production-relationships.md').write_text('\n'.join(md),encoding='utf-8')
print(f'Built {len(objects)} objects; {len(relations)} reference-target pairs; {len([r for r in relations if r["tier"]=="core"])} core pairs; {len(candidates)} candidate joins.')
