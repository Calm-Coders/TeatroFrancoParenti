# TFP production relationships for Tableau

**Aggiornamento 25/09/2026:** [modello relazionale delle agevolazioni](catalog-advantages-tableau.md) ora disponibile in produzione. Il resto di questo atlante fotografa l'audit precedente alla distribuzione.

Production: **Teatro Franco Parenti** · Read-only audit started 2026-09-25T13:52:27.884393+00:00 · Key checks ended 2026-09-25T14:02:44.981305+00:00

Read-only production audit of 28 TFP business objects, plus 36 administrative, CRM and Marketing Cloud extension objects. Every reference field on those 64 objects is inventoried, including administrative and polymorphic references. Counts were collected over several minutes, exclude deleted records, reflect the CLI user and may differ slightly between queries. Match percentages measure source population or stated text-key matching, not automatic Tableau readiness.

## Findings

### Dove si prendono le agevolazioni

There are two SecuTix sources. Product agevolazioni are in the catalog resolve response advantages[] and saved as Inventory__c.Product_Advantages__c JSON. The exported product-advantages.csv has 141 product–advantage links across 71 products and 39 distinct advantage IDs. Customer agevolazioni come from the contact webhook: Account.Advantages__c stores its advantages[] JSON, and Account.Has_Advantages__c stores its hasAdvantages flag (23,013 true). The 2026-09-25 deployment adds Catalog_Advantage__c and Catalog_Advantage_Product__c. For new Tableau reports, use these relational objects; treat Account eligibility separately.

Evidence: Deployed CatalogEnrichmentService, Deployed ContactRestResource, product-advantages.csv

### Start with the real sales chain

Account ← Order ← Order_Operation_Data__c ← Order_Movement_Data__c is the central path. All profiled orders have AccountId, and every operation and movement has its parent links. Inventory__c is the catalog dimension; Product2 and OrderItem are empty.

Evidence: profiles.json, Production sObject describes

### Product matching can improve; access links remain sparse

324,527 / 934,482 operations have the native Inventory__c lookup (34.7%). The separately checked Product_Id__c → Inventory_Id__c text-key candidate matches 569,549 / 934,490 operations (60.9%), so native lookup population understates possible current product matching. Access_Control__c has only 1 / 8,503 Order__c links and 0 / 8,503 Inventory__c links. Preserve unmatched rows explicitly.

Evidence: profiles.json, candidate-profiles.json

### A useful performance relationship exists only as a text-key candidate

Operation.Performance_Id__c can match Performance.Performance_Id__c: 509,986 of 934,484 operations match the current catalog, from 541,482 nonblank source keys. All 3,414 target keys are distinct now, but uniqueness is not enforced. Operation.Performance__c itself is a label.

Evidence: candidate-profiles.json, reporting-metrics.json

### Price-by-seat analysis is currently incomplete

All 2,936 performance prices link to performance and audience, but none has Seat_Category__c or its source Seat_Category_Id__c. Separately, 1,374 performance-to-seat-category bridge rows exist. Those bridges do not prove which price belongs to which seat category.

Evidence: profiles.json, reporting-metrics.json

### Keep each measure at its native row grain

An illustrative order with 2 operations and 3 independent access rows can become 6 rows when physically joined on Order. A €100 header would then sum to €600. Relate tables at their own grain or aggregate each branch first. COUNTD prevents duplicated IDs, but does not repair duplicated monetary sums. Relationships also do not allocate a header amount across products or an operation amount across seats: use a measure at the reporting grain or define an allocation rule.

Evidence: Tableau data model, Cardinality and referential integrity

### Plan refreshes around delete-and-recreate integrations

Order updates rebuild operations and movements; catalog updates can rebuild performances and children. Their Salesforce Ids may change. Start with full extract refreshes or a deletion-aware staging process; append-only incremental loads can retain stale rows and duplicate totals.

Evidence: Deployed OrderRestResource, Deployed InventoryRestResource

### Define sales, refunds and package counting before KPI creation

The live operation types include SALE, PRE_SALE, RESERVATION, ABANDON, refund and cancellation variants; kinds include SINGLE_ENTRY, CHARGES and composition. Standard Order.Status is Draft throughout. Agree Order_State__c, Type__c and Kind__c filters and avoid counting both package parents and components. No net-revenue or attendance formula is asserted here.

Evidence: reporting-metrics.json, Deployed OrderRestResource

### Amount scales differ by integration

Deployed order/operation code normalizes incoming money by 1,000. For numeric/unformatted source amounts, performance-price code uses 1,000 and membership code uses 100; their helpers preserve already formatted decimal strings. These stored amounts must not be divided again. Access_Control.Price__c stores input unchanged, so reconcile its unit before comparing it with sales amounts. Catalog Amount__c describes configured price, not realized revenue.

Evidence: Deployed integration classes, code-verification.json

### Use conservative Tableau relationship settings

For a single-target Salesforce foreign key → parent Id, the structural child-to-parent cardinality is Many-to-one; no reverse one-to-one claim is made. Use Some records match unless the actual extracted rows prove otherwise. For unvalidated text joins, leave Many-to-many / Some records match until uniqueness and coverage are checked. Native schema constraints do not guarantee matching after extract filters or permissions.

Evidence: Cardinality and referential integrity

### Prepare the extract deliberately

Use individual Salesforce objects under Table, then create logical relationships. The native Salesforce connector is extract-only; prejoined Standard Connections limit modeling flexibility. Tableau documents that calculated fields and long text over 4,096 characters are excluded from extracts: test required formulas and use typed child objects rather than raw JSON. Custom SQL and cross-database Salesforce models also have incremental-refresh restrictions.

Evidence: Salesforce connector, Relate your data

### Separate the full source graph from Tableau subject areas

The source has loops: Movement connects directly and through Operation to Order; product composition returns to Inventory; price and category branches share Performance. Tableau cannot reproduce every path in one logical tree. Select one path per subject area, or use separately named purchaser/holder, source/target-product and other role copies. Multi-fact modeling needs a compatible Tableau version and carefully chosen shared dimensions.

Evidence: Build a multi-fact model, When to use multi-fact relationships, Multi-fact analysis behavior

### What still needs an implementation decision

Dashboard/KPI definitions, Tableau version, native Salesforce versus warehouse route, refresh frequency, timezone, refund sign conventions and historical retention remain unspecified. No Tableau workbook or data-source deployment is included. The object/relationship inventory covers the TFP custom model plus identified CRM and package extensions; it is not a complete inventory of every Salesforce system object.

Evidence: Scope of this artifact

## Recommended subject areas

### 01 · Order and customer reporting

Base: Order

Use Order.AccountId → Account.Id as purchaser. Aggregate Sale_Amount__c and other header amounts once per order. Count distinct Order.Id for current orders; distinguish identified customers from fallback accounts.

### 02 · Product and performance sales

Base: Order_Operation_Data__c

Use the operation → Order → purchaser path. For Inventory choose the native lookup or the more complete validated Product_Id__c → Inventory_Id__c candidate, then preserve unmatched products. Add candidate performance/audience/seat joins only with validated keys and unmatched buckets. If Performance is linked directly by text key, avoid a second path back to the same Inventory node through Event. Sum operation amounts only after defining state, type, kind, refunds and package rules.

### 03 · Seat movements and holders

Base: Order_Movement_Data__c

Use Movement → Operation → Order for the sales path. Add a separate Account role for Movement.Account__c (holder) and Order.AccountId (purchaser). Native movement counts are not necessarily admissions or attendance.

### 04 · Catalog and configured prices

Base: Performance_Price__c

Use Price → Performance → Event → Inventory and optional Venue/Audience. Price.Seat_Category__c is empty today; do not infer a price-to-seat join from the separate Performance_Seat_Category bridge. Charge branches are schema-only until populated.

### 05 · Selling windows and restrictions

Base: Sale_Period__c

Model one parent role at a time using Parent_Type__c. Audience and seat restrictions are independent children. Keep them as separate logical branches or preaggregate restrictions; do not flatten their Cartesian combinations.

### 06 · Packs, subscriptions and memberships

Base: Package_Line__c / Season_Ticket_Line__c / Membership_Item__c

Use separate subject areas for each composition fact. Treat parent product and target component product as separate Inventory roles. These rows describe offers, eligibility and recommendations, not customer purchases or entitlements.

### 07 · Access-control data quality

Base: Access_Control__c

Begin with completeness/state reporting at barcode grain. Only one order lookup and no inventory lookups are populated; 8,498 of 8,503 rows lack Ticket_State__c. Attendance and ticket-to-sales reconciliation need additional source coverage and defined event semantics.

### 08 · Optional CRM / marketing

Base: Opportunity / CampaignMember

Keep pipeline and campaign reporting separate until ticketing attribution keys are established. The 50 opportunities, 3 campaigns and 15 campaign memberships are small optional branches; orders currently have no OpportunityId link. Marketing-package schema is inventoried in the object explorer.

## Core objects

### Access_Control__c

Access · 8,503 rows

Current snapshot: one record per populated unique Barcode__c; upserted state, not an immutable scan-event log.

- Order__c and Inventory__c are real lookups but are almost entirely empty in this snapshot.
- All current rows have a barcode. The schema permits blank barcodes, and those payloads can insert additional records.
- COUNT of rows is a barcode-record count, not verified attendance or scan count. Group_Size__c can represent multiple people.
- Price__c stores the incoming value unchanged. Its unit is not established as equal to order currency values.
- No native Account, Performance or Movement lookup exists. Do not join barcode to Movement_Id__c or assume Ticket_Id__c is a movement key.

- `Access_Control__c.Inventory__c → Inventory__c.Id` · Lookup · N:1 · nullable · 0/8,503 populated
- `Access_Control__c.Order__c → Order.Id` · Lookup · N:1 · nullable · 1/8,503 populated

### Account

Customers · 101,476 rows

One current customer or organization account; SecuTix contacts are loaded here.

- Contact_Number__c is the unique external customer key. Account.ParentId relates an individual to an organization where supplied.
- Customer agevolazioni arrive as advantages[] and hasAdvantages in the SecuTix contact webhook. Account.Advantages__c stores the raw JSON and Account.Has_Advantages__c stores the flag; 23,013 Accounts currently have the flag true. This describes customer eligibility, not a proven purchased discount.
- Use separate purchaser and movement-holder roles. Monthly anonymous fallback accounts exist; distinct Account counts are not automatically identified-customer counts.

- `Account.MasterRecordId → Account.Id` · Standard reference · N:1 · nullable · 0/101,476 populated
- `Account.RecordTypeId → RecordType.Id` · Standard reference · N:1 · nullable · 101,471/101,476 populated
- `Account.ParentId → Account.Id` · Standard reference · N:1 · nullable · 98/101,476 populated

### Audience_Sub_Category__c

Pricing · 38 rows

One catalog audience/tariff subcategory with unique Audience_Subcategory_Id__c.

- Used by prices, sale eligibility and forced package-line audience. Audience_Key__c is also unique.
- The spelling differs from Order_Operation_Data__c.Audience_SubCategory_Id__c; use exact API names shown in the candidate join.


### Charge_Component__c

Pricing · 0 rows

One reusable charge definition identified by Charge_Id__c / Charge_Key__c.

- Schema exists but the object has zero current rows. Do not equate catalog charge definitions with order CHARGES operations.


### Cross_Sell_Product_Link__c

Composition · 4 rows

One directed source-product → recommended-target-product relationship.

- Both Source_Inventory__c and Target_Inventory__c point to Inventory. Use separate source/target roles and do not treat recommendation links as transactions.

- `Cross_Sell_Product_Link__c.Source_Inventory__c → Inventory__c.Id` · Master-detail · N:1 · required · 4/4 populated
- `Cross_Sell_Product_Link__c.Target_Inventory__c → Inventory__c.Id` · Lookup · N:1 · nullable · 4/4 populated

### Inventory_Event__c

Catalog · 865 rows

One event-detail row linked to a catalog inventory product.

- Follow Inventory__c to product, and incoming Performance__c.Inventory_Event__c for scheduled performances.
- The source models this as a subtype, but metadata does not enforce a one-to-one inventory/event relationship. Use N:1 child-to-parent unless separately proven.

- `Inventory_Event__c.Inventory__c → Inventory__c.Id` · Lookup · N:1 · nullable · 865/865 populated

### Inventory__c

Catalog · 1,058 rows

One current catalog product per unique Inventory_Id__c.

- This is the ticketing product dimension. Standard Salesforce Product2 and OrderItem have zero rows in this snapshot.
- Product agevolazioni arrive as advantages[] in the SecuTix catalog resolve response and are saved in Product_Advantages__c as JSON text. The current export has 141 product-to-advantage links across 71 products and 39 distinct advantage IDs. Use product-advantages.csv as a Tableau bridge: Inventory_Salesforce_Id → Inventory__c.Id.
- There is no Advantage__c business object or native lookup from Inventory to an advantage. Customer Account.Advantages__c is a separate contact payload, so no product-to-customer advantage relationship is asserted.
- Contains product family, season and translated descriptions. Some nested source arrays remain JSON; typed child objects provide usable relations.
- Current product state can replace earlier season metadata. Preserve order snapshots or separate history for historical product/season attributes.


### Membership_Item_Price__c

Composition · 0 rows

One configured price occurrence for a membership item and audience.

- Zero current rows. Catalog monetary fields are normalized by the integration; do not divide them again.

- `Membership_Item_Price__c.Audience_Sub_Category__c → Audience_Sub_Category__c.Id` · Lookup · N:1 · nullable · 0/0 populated
- `Membership_Item_Price__c.Membership_Item__c → Membership_Item__c.Id` · Master-detail · N:1 · required · 0/0 populated

### Membership_Item__c

Composition · 13 rows

One membership item/option under a membership product.

- Relationship_Key__c is unique. Prices and eligibility periods are further child branches; their current price branch is empty.

- `Membership_Item__c.Membership__c → Membership__c.Id` · Master-detail · N:1 · required · 13/13 populated

### Membership__c

Composition · 13 rows

One membership product-detail row linked to inventory.

- Catalog offer definition, not a customer membership purchase or entitlement record.

- `Membership__c.Inventory__c → Inventory__c.Id` · Lookup · N:1 · nullable · 13/13 populated

### Order

Sales · 409,280 rows

One current order header, keyed by Order_Id__c or Order_Secret_Id__c.

- Aggregate header amounts at Order grain. Use Order_State__c for business state; all profiled standard Status values are Draft.
- Product_Id__c is only the first non-CHARGES product. Use operations for the complete basket.
- Creation_Date_Time__c and Reference_Date__c are text: parse and validate timezone before using a date dimension.

- `Order.ContractId → Contract.Id` · Standard reference · N:1 · nullable · 0/409,280 populated
- `Order.AccountId → Account.Id` · Standard reference · N:1 · nullable · 409,280/409,280 populated
- `Order.Pricebook2Id → Pricebook2.Id` · Standard reference · N:1 · nullable · 0/409,280 populated
- `Order.OriginalOrderId → Order.Id` · Standard reference · N:1 · nullable · 0/409,280 populated
- `Order.OpportunityId → Opportunity.Id` · Standard reference · N:1 · nullable · 0/409,280 populated
- `Order.QuoteId → Quote.Id` · Standard reference · N:1 · nullable · 0/409,280 populated
- `Order.CustomerAuthorizedById → Contact.Id` · Standard reference · N:1 · nullable · 0/409,280 populated
- `Order.CompanyAuthorizedById → User.Id` · Standard reference · N:1 · nullable · 0/409,280 populated
- `Order.BillToContactId → Contact.Id` · Standard reference · N:1 · nullable · 0/409,280 populated
- `Order.ShipToContactId → Contact.Id` · Standard reference · N:1 · nullable · 0/409,280 populated
- `Order.ActivatedById → User.Id` · Standard reference · N:1 · nullable · 0/409,280 populated

### Order_Movement_Data__c

Sales · 1,073,649 rows

One seat/movement from the latest order payload; optionally associated with a holder account.

- Order_Operation_Data__c identifies the exact operation. Order__c supplies a direct header link. Account__c is the holder role, not necessarily the buyer.
- Avoid two routes from Movement to Order in the same Tableau relationship tree: use Movement → Operation → Order, or a deliberate alternative.
- Movement_Id__c has no uniqueness constraint; validate order + movement business key. Salesforce Id changes when order children are rebuilt.
- Seat_Category__c is text; a candidate Seat_Category_Id__c join is only partially covered by the current catalog.

- `Order_Movement_Data__c.Account__c → Account.Id` · Lookup · N:1 · nullable · 889,264/1,073,649 populated
- `Order_Movement_Data__c.Order_Operation_Data__c → Order_Operation_Data__c.Id` · Lookup · N:1 · nullable · 1,073,649/1,073,649 populated
- `Order_Movement_Data__c.Order__c → Order.Id` · Lookup · N:1 · nullable · 1,073,649/1,073,649 populated

### Order_Operation_Data__c

Sales · 934,482 rows

One operation from the latest order payload; operations include admissions, composition, charges, refunds and reservations.

- Order__c is the header lookup; Inventory__c is the current product lookup. Parent_Operation__c expresses composition/parentage.
- Performance__c, Audience_SubCategory__c and Seat_Category__c are text labels, not lookups. Candidate text-ID relationships are listed separately.
- Operation_Id__c is not metadata-unique. Validate Order business key + Operation_Id__c before using a durable warehouse key.
- Recreated on order update: Salesforce Id is a current row key, not a stable historical business key. Do not sum Unit_Price__c as revenue; define filters and package/charge handling before summing totals.

- `Order_Operation_Data__c.Inventory__c → Inventory__c.Id` · Lookup · N:1 · nullable · 324,527/934,482 populated
- `Order_Operation_Data__c.Order__c → Order.Id` · Lookup · N:1 · nullable · 934,482/934,482 populated
- `Order_Operation_Data__c.Parent_Operation__c → Order_Operation_Data__c.Id` · Lookup · N:1 · nullable · 371,316/934,482 populated

### Pack__c

Composition · 35 rows

One package product-detail row linked to inventory.

- A catalog package definition. Use Order operations to analyze actual package purchases.

- `Pack__c.Inventory__c → Inventory__c.Id` · Lookup · N:1 · nullable · 35/35 populated

### Package_Line__c

Composition · 112 rows

One source package line within a pack, identified by Relationship_Key__c.

- Pack__c is its parent. Target_Inventory__c identifies the contained product; Forced_Audience_Sub_Category__c optionally constrains audience.
- All 112 target-inventory links are populated; 101 have forced audience, and the remaining 11 may be intentionally unrestricted.
- Parent_Package_Line__c is a self-reference, currently unpopulated. Target product requires a separate Inventory role from the pack product.

- `Package_Line__c.Forced_Audience_Sub_Category__c → Audience_Sub_Category__c.Id` · Lookup · N:1 · nullable · 101/112 populated
- `Package_Line__c.Pack__c → Pack__c.Id` · Master-detail · N:1 · required · 112/112 populated
- `Package_Line__c.Parent_Package_Line__c → Package_Line__c.Id` · Lookup · N:1 · nullable · 0/112 populated
- `Package_Line__c.Target_Inventory__c → Inventory__c.Id` · Lookup · N:1 · nullable · 112/112 populated

### Performance_Price_Charge__c

Pricing · 0 rows

One charge occurrence under a configured performance price.

- Schema exists but there are zero current rows. Keep this branch available only if charge data is subsequently populated.

- `Performance_Price_Charge__c.Charge_Component__c → Charge_Component__c.Id` · Lookup · N:1 · nullable · 0/0 populated
- `Performance_Price_Charge__c.Performance_Price__c → Performance_Price__c.Id` · Master-detail · N:1 · required · 0/0 populated

### Performance_Price__c

Pricing · 2,936 rows

One configured performance price occurrence with optional audience and seat category.

- Price_Key__c is unique; source duplicates can receive occurrence suffixes. Do not assume Performance + Audience alone is a unique key.
- Configured catalog price is not realized sale revenue. All 2,936 rows have audience and performance links; none has Seat_Category__c or Seat_Category_Id__c populated.
- Relating prices to all performance seat categories would not recover a proven seat-specific price mapping.

- `Performance_Price__c.Audience_Sub_Category__c → Audience_Sub_Category__c.Id` · Lookup · N:1 · nullable · 2,936/2,936 populated
- `Performance_Price__c.Performance__c → Performance__c.Id` · Master-detail · N:1 · required · 2,936/2,936 populated
- `Performance_Price__c.Seat_Category__c → Seat_Category__c.Id` · Lookup · N:1 · nullable · 0/2,936 populated

### Performance_Seat_Category__c

Pricing · 1,374 rows

One performance-to-seat-category bridge row.

- The bridge expresses which seat categories are associated with a performance. Its unique Relationship_Key__c is the stored compound relationship key.
- Multiple categories per performance multiply rows if flattened into the performance or price fact.

- `Performance_Seat_Category__c.Performance__c → Performance__c.Id` · Master-detail · N:1 · required · 1,374/1,374 populated
- `Performance_Seat_Category__c.Seat_Category__c → Seat_Category__c.Id` · Lookup · N:1 · required · 1,374/1,374 populated

### Performance__c

Catalog · 3,414 rows

One current scheduled performance under an inventory event.

- Start__c is a typed datetime. Venue_Location__c is the real venue lookup.
- Performance_Id__c is text with no uniqueness constraint; all 3,414 current values were present and distinct in the key check.
- Catalog refresh can delete and recreate these rows and dependent children. Use a full refresh or deletion-aware extraction.

- `Performance__c.Inventory_Event__c → Inventory_Event__c.Id` · Lookup · N:1 · nullable · 3,414/3,414 populated
- `Performance__c.Venue_Location__c → Venue_Location__c.Id` · Lookup · N:1 · nullable · 506/3,414 populated

### Sale_Period_Audience__c

Availability · 1,660 rows

One audience restriction under a sale period.

- Links a period to Audience_Sub_Category__c. Multiple audiences and seat restrictions are separate one-to-many branches; joining both physically creates combinations.

- `Sale_Period_Audience__c.Audience_Sub_Category__c → Audience_Sub_Category__c.Id` · Lookup · N:1 · nullable · 1,660/1,660 populated
- `Sale_Period_Audience__c.Sale_Period__c → Sale_Period__c.Id` · Master-detail · N:1 · required · 1,660/1,660 populated

### Sale_Period_Seat_Category__c

Availability · 5,326 rows

One source seat-category restriction under a sale period.

- Sale_Period__c is a lookup. Seat_Category_Id__c is text, with no native lookup to Seat_Category__c. Candidate text join has 48 unmatched rows in this snapshot.

- `Sale_Period_Seat_Category__c.Sale_Period__c → Sale_Period__c.Id` · Master-detail · N:1 · required · 5,326/5,326 populated

### Sale_Period__c

Availability · 476 rows

One selling window for an inventory, performance or membership-item price.

- Parent_Type__c determines the parent role. Current rows: 14 Inventory windows and 462 Performance windows; zero Membership Item Price windows.
- Start__c / End__c, sale/reservation/quotation flags and Sales_Channel__c describe selling eligibility, not purchases.

- `Sale_Period__c.Inventory__c → Inventory__c.Id` · Lookup · N:1 · nullable · 14/476 populated
- `Sale_Period__c.Membership_Item_Price__c → Membership_Item_Price__c.Id` · Lookup · N:1 · nullable · 0/476 populated
- `Sale_Period__c.Performance__c → Performance__c.Id` · Lookup · N:1 · nullable · 462/476 populated
- `Sale_Period__c.Sales_Channel__c → Sales_Channel__c.Id` · Lookup · N:1 · nullable · 476/476 populated

### Sales_Channel__c

Availability · 1 rows

One catalog selling channel keyed by Channel_Key__c.

- Order.Sales_Channel_Code__c is an attribute, not a lookup to this object. A code join requires uniqueness and coverage checks.
- One catalog channel exists now; do not assume it covers all historical order channels.


### Season_Ticket_Line__c

Composition · 612 rows

One season-ticket composition line under a season-ticket product.

- Target_Inventory__c identifies its component product; Subject__c optionally groups a line under a subject.
- All 612 lines have target inventory; none currently has Subject__c.

- `Season_Ticket_Line__c.Season_Ticket__c → Season_Ticket__c.Id` · Master-detail · N:1 · required · 612/612 populated
- `Season_Ticket_Line__c.Subject__c → Season_Ticket_Subject__c.Id` · Lookup · N:1 · nullable · 0/612 populated
- `Season_Ticket_Line__c.Target_Inventory__c → Inventory__c.Id` · Lookup · N:1 · nullable · 612/612 populated

### Season_Ticket_Subject__c

Composition · 0 rows

One subject/group within a season-ticket definition.

- Zero current rows. Subject membership is represented by Season_Ticket_Line__c.Subject__c when populated.

- `Season_Ticket_Subject__c.Season_Ticket__c → Season_Ticket__c.Id` · Master-detail · N:1 · required · 0/0 populated

### Season_Ticket__c

Composition · 44 rows

One season-ticket product-detail row linked to inventory.

- A catalog composition definition, not the fact of a customer owning a season ticket.

- `Season_Ticket__c.Inventory__c → Inventory__c.Id` · Lookup · N:1 · nullable · 44/44 populated

### Seat_Category__c

Pricing · 30 rows

One catalog seat category with unique Seat_Category_Id__c and Category_Key__c.

- Reusable dimension for performance/category bridges. Operational text IDs only partially match this current catalog.


### Venue_Location__c

Catalog · 9 rows

One reusable site/space location, identified by Location_Key__c.

- Site and space names/codes are descriptive attributes. Follow Performance__c.Venue_Location__c; do not join on venue labels.


## Candidate text-key joins

- `Order_Operation_Data__c.Seat_Category_Id__c → Seat_Category__c.Seat_Category_Id__c` — **Validated current keys; partial coverage**. Text-key candidate, not a Salesforce lookup. 115,864 of 934,484 child rows match the current target; 565,664 child rows have a source key. Target: 30 distinct nonblank keys across 30 rows.
- `Order_Operation_Data__c.Audience_SubCategory_Id__c → Audience_Sub_Category__c.Audience_Subcategory_Id__c` — **Validated current keys; partial coverage**. Text-key candidate, not a Salesforce lookup. 362,090 of 934,484 child rows match the current target; 934,484 child rows have a source key. Target: 38 distinct nonblank keys across 38 rows.
- `Order_Movement_Data__c.Seat_Category_Id__c → Seat_Category__c.Seat_Category_Id__c` — **Validated current keys; partial coverage**. Text-key candidate, not a Salesforce lookup. 215,108 of 1,073,651 child rows match the current target; 1,067,564 child rows have a source key. Target: 30 distinct nonblank keys across 30 rows.
- `Sale_Period_Seat_Category__c.Seat_Category_Id__c → Seat_Category__c.Seat_Category_Id__c` — **Validated current keys; partial coverage**. Text-key candidate, not a Salesforce lookup. 5,278 of 5,326 child rows match the current target; 5,326 child rows have a source key. Target: 30 distinct nonblank keys across 30 rows.
- `Access_Control__c.Product_Id__c → Inventory__c.Inventory_Id__c` — **Blocked: no current matches**. Text-key candidate, not a Salesforce lookup. 0 of 8,503 child rows match the current target; 5 child rows have a source key. Target: 1,058 distinct nonblank keys across 1,058 rows.
- `Order_Operation_Data__c.Performance_Id__c → Performance__c.Performance_Id__c` — **Validated current keys; partial coverage**. Text-key candidate, not a Salesforce lookup. 509,986 of 934,484 child rows match the current target; 541,482 child rows have a source key. Target: 3,414 distinct nonblank keys across 3,414 rows. Current key uniqueness is observed, not enforced. Recheck each refresh and preserve unmatched historical operations.
- `Order_Operation_Data__c.Product_Id__c → Inventory__c.Inventory_Id__c` — **Validated current keys; partial coverage**. Text-key candidate, not a Salesforce lookup. 569,549 of 934,490 child rows match the current target; 934,490 child rows have a source key. Target: 1,058 distinct nonblank keys across 1,058 rows. Target Inventory_Id__c is metadata-unique. This text-key mapping covers more current rows than the native lookup; use one deliberate product relationship, not both paths to the same Inventory table.
- `Order.Sales_Channel_Code__c → Sales_Channel__c.Code__c` — **Proposed; not profiled**. No native lookup. Code__c is not unique by metadata. Validate uniqueness, scope and historical coverage; retain order channel attributes when the catalog lacks channels.
- `Access_Control__c.Order_Id__c → Order.Order_Id__c` — **Incomplete source; not matched independently**. Only 5 of 8,503 access rows have Order_Id__c. Prefer the existing Order__c lookup when available (1 populated); direct text-key coverage was not independently measured.
- `Access_Control__c.Cultural_Contact_Number__c → Account.Contact_Number__c` — **Proposed; identity role unverified**. Only 4 of 8,503 rows have a cultural contact number. Confirm its business role and matching coverage before treating it as a buyer or ticket-holder relationship.

## Sources

- Product advantage bridge export — `outputs/tableau-production/product-advantages.csv`. Read-only 2026-09-25 extract from Inventory__c.Product_Advantages__c. One row per product × advantage, with product IDs, advantage ID/code, translated names and target type; no customer data.
- Live Salesforce production schema — `.local/tableau-production/describe/`. 64 REST sObject describes through the existing TFA Prod CLI session. Organization.IsSandbox=false; fields, references, nullability and unique/external-ID flags verified.
- Production row counts and lookup population — `.local/tableau-production/profiles.json`. Read-only COUNT(Id) and COUNT(reference field) per object. Nondeleted rows visible to the CLI user. A populated foreign key is not an independently tested Tableau extract match.
- Candidate key coverage and uniqueness — `.local/tableau-production/candidate-profiles.json`. Target text keys and aggregate child counts only; no customer record values are included in the artifact.
- State, key and field availability checks — `.local/tableau-production/reporting-metrics.json`. Read-only grouped states/types and aggregate completeness checks. Collection is not a transactionally consistent snapshot; production changes between queries.
- Deployed Apex verification — `.local/tableau-production/code-verification.json`. Production integration code checked against repository implementations; the copied code stays local.
- Catalog integration and production promotion — `docs/local-catalog-salesforce-sync.md`. Production promotion 2026-08-27; typed catalog relationships, normalization and refresh behavior. Earlier UAT counts are not used as current production counts.
- [Tableau data model](https://help.tableau.com/current/pro/desktop/en-us/datasource_datamodel.htm). Logical relationships retain native table grain; physical joins combine rows.
- [Cardinality and referential integrity](https://help.tableau.com/current/pro/desktop/en-us/cardinality_and_ri.htm). Default to conservative match settings; do not declare complete matching without validating actual extracts.
- [Salesforce connector](https://help.tableau.com/current/pro/desktop/en-us/examples_salesforce.htm). Custom objects; extracts only; connector and refresh restrictions.
- [Relate your data](https://help.tableau.com/current/pro/desktop/en-us/relate_tables.htm). Use individual objects instead of prejoined Standard Connection templates when building relationships.
- [Build a multi-fact model](https://help.tableau.com/current/pro/desktop/en-us/datasource_mfr_build.htm). Avoid cycles, repeated downstream paths and unsupported nested shared tables.
- [When to use multi-fact relationships](https://help.tableau.com/current/pro/desktop/en-us/datasource_mfr_when_to_use.htm). Multi-base models require Tableau 2024.2 or later; prefer a single base when sufficient.
- [Multi-fact analysis behavior](https://help.tableau.com/current/pro/desktop/en-us/datasource_mfr_multiple_base_tables.htm). Shared dimensions must participate in the view to stitch facts; filter-only fields are insufficient.

The HTML explorer and accompanying CSVs contain all optional/support objects and every reference on the 64 profiled objects. No production data or metadata was modified.
