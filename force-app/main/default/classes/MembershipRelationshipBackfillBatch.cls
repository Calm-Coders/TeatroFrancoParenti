public without sharing class MembershipRelationshipBackfillBatch
    implements Database.Batchable<SObject>, Database.Stateful {
    public Integer invalidPayloads = 0;
    public Integer itemsUpserted = 0;
    public Integer itemsDeleted = 0;
    public Integer pricesUpserted = 0;
    public Integer pricesDeleted = 0;
    public Integer salePeriodsUpserted = 0;
    public Integer salePeriodsDeleted = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Items__c
            FROM Membership__c
        ]);
    }

    public void execute(Database.BatchableContext context, List<Membership__c> scope) {
        MembershipRelationshipService.Stats stats =
            MembershipRelationshipService.syncStoredMemberships(scope);
        invalidPayloads += stats.invalidPayloads;
        itemsUpserted += stats.itemsUpserted;
        itemsDeleted += stats.itemsDeleted;
        pricesUpserted += stats.pricesUpserted;
        pricesDeleted += stats.pricesDeleted;
        salePeriodsUpserted += stats.salePeriodsUpserted;
        salePeriodsDeleted += stats.salePeriodsDeleted;
    }

    public void finish(Database.BatchableContext context) {
    }
}
