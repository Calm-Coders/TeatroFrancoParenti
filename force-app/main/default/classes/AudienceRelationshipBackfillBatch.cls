public without sharing class AudienceRelationshipBackfillBatch implements Database.Batchable<SObject>, Database.Stateful {
    public Integer audiencesUpserted = 0;
    public Integer restrictionsLinked = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Audience_Subcategory_Id__c, Code__c, Name_IT__c, Kind__c,
                   Audience_Sub_Category__c
            FROM Sale_Period_Audience__c
        ]);
    }
    public void execute(Database.BatchableContext context, List<Sale_Period_Audience__c> scope) {
        PerformancePriceRelationshipService.Stats stats =
            PerformancePriceRelationshipService.syncStoredSalePeriodAudiences(scope);
        audiencesUpserted += stats.audiencesUpserted;
        restrictionsLinked += stats.salePeriodAudiencesLinked;
    }
    public void finish(Database.BatchableContext context) {}
}
