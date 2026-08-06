public with sharing class SeatCategoryBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
    public Integer categoriesUpserted = 0;
    public Integer linksUpserted = 0;
    public Integer linksDeleted = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Seat_Categories__c FROM Performance__c
        ]);
    }

    public void execute(Database.BatchableContext context, List<Performance__c> scope) {
        SeatCategoryRelationshipService.Stats stats = SeatCategoryRelationshipService.syncStoredPerformances(scope);
        categoriesUpserted += stats.categoriesUpserted;
        linksUpserted += stats.linksUpserted;
        linksDeleted += stats.linksDeleted;
    }

    public void finish(Database.BatchableContext context) {}
}
