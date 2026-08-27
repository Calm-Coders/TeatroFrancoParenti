public without sharing class PerformancePriceBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
    public Integer audiencesUpserted = 0;
    public Integer pricesUpserted = 0;
    public Integer pricesDeleted = 0;
    public Integer priceChargesUpserted = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Prices__c, Tariff_Legend__c FROM Performance__c
        ]);
    }
    public void execute(Database.BatchableContext context, List<Performance__c> scope) {
        PerformancePriceRelationshipService.Stats stats =
            PerformancePriceRelationshipService.syncStoredPerformances(scope);
        audiencesUpserted += stats.audiencesUpserted;
        pricesUpserted += stats.pricesUpserted;
        pricesDeleted += stats.pricesDeleted;
        priceChargesUpserted += stats.priceChargesUpserted;
    }
    public void finish(Database.BatchableContext context) {}
}
