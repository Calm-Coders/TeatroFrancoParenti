public without sharing class PackageLineRelationshipBackfillBatch
    implements Database.Batchable<SObject>, Database.Stateful {
    public Integer invalidPayloads = 0;
    public Integer linesUpserted = 0;
    public Integer linesDeleted = 0;
    public Integer audiencesUpserted = 0;
    public Integer parentLookupsLinked = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Package_Lines__c
            FROM Pack__c
        ]);
    }

    public void execute(Database.BatchableContext context, List<Pack__c> scope) {
        PackageLineRelationshipService.Stats stats =
            PackageLineRelationshipService.syncStoredPacks(scope);
        invalidPayloads += stats.invalidPayloads;
        linesUpserted += stats.linesUpserted;
        linesDeleted += stats.linesDeleted;
        audiencesUpserted += stats.audiencesUpserted;
        parentLookupsLinked += stats.parentLookupsLinked;
    }

    public void finish(Database.BatchableContext context) {
    }
}
