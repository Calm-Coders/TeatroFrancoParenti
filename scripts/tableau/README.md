# Production relationship artifact

The delivered explainer is `outputs/tableau-production/tableau-production-relationships.html`.
It is a standalone, offline HTML artifact. The CSVs and Markdown report in the same
directory provide portable handoff formats.

`product-advantages.csv` is a current, read-only export of catalog-product advantages:
one row for each product × advantage. Join its `Inventory_Salesforce_Id` to
`Inventory__c.Id` in Tableau. Customer advantages remain in `Account.Advantages__c`
JSON and `Account.Has_Advantages__c`; they do not have an audited direct relationship
to the product advantage rows.

## Evidence

The 2026-09-25 audit used the existing **TFA Prod** Salesforce CLI login. It verified
`Organization.IsSandbox = false`, described 64 relevant objects, measured current
nondeleted row counts and lookup population, checked selected text-key joins, and
compared 12 deployed Apex classes with repository implementations. All production
operations were read-only. No row-level customer data is included in the artifact.

Local evidence lives in `.local/tableau-production/`; deployed Apex copies and full
describes stay there. The distributed model contains field names/types, relationships,
aggregate statistics and explanatory notes only.

Counts came from independent queries over several minutes. Production changed during
collection, so small differences between profile counts and later candidate checks are
expected. These are not transactionally consistent snapshots. Lookup population does
not prove that a filtered/permission-limited Tableau extract contains every parent.

## Regeneration

From the repository root, with the same authorized Salesforce CLI access:

```powershell
python scripts/tableau/inspect_production.py
python scripts/tableau/profile_reporting_keys.py
python scripts/tableau/export_advantages.py
python scripts/tableau/build_model.py
python scripts/tableau/render_artifact.py
```

The inspection scripts perform only describes, object listing and SELECT queries.
`inspect_production.py` refreshes schema data on each run. The model builder contains
editorial observations for the **2026-09-25 snapshot**: review and update those notes,
counts and deployed-code evidence before publishing a later snapshot. It does not
automatically certify a new audit or derive KPI definitions.

The HTML renderer consumes `.local/tableau-production/model.json`; its output is
`.lavish/tableau-production-relationships.html`. Copy the verified HTML to `outputs`
for handoff. The design follows `docs/integration-explorer.html`.

## Scope

- 28 core TFP business objects and all 45 references between them.
- 36 optional CRM, Marketing Cloud, and support objects; all their reference fields
  are inventoried too, including audit fields and polymorphic targets.
- Ten candidate text-key relationships, separated from native Salesforce references.
- Platform events, trending objects and referenced system targets outside this scope
  are identified explicitly. This is not an exhaustive dump of Salesforce system objects.

No Salesforce deployment, Tableau connection, workbook or published data source was
created by this work. Refresh strategy, KPI filters, monetary reconciliation and
historical requirements need to be decided before implementing dashboards.
