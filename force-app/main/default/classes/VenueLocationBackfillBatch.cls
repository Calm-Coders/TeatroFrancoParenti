public without sharing class VenueLocationBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
    public Integer locationsUpserted = 0;
    public Integer performancesLinked = 0;
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Location__c, Site_Code__c, Space_Code__c,
                   Site_Name_IT__c, Site_Name_EN__c, Space_Name_IT__c, Space_Name_EN__c
            FROM Performance__c
        ]);
    }
    public void execute(Database.BatchableContext context, List<Performance__c> scope) {
        VenueLocationRelationshipService.Stats stats = VenueLocationRelationshipService.syncStoredPerformances(scope);
        locationsUpserted += stats.locationsUpserted;
        performancesLinked += stats.performancesLinked;
    }
    public void finish(Database.BatchableContext context) {}
}
