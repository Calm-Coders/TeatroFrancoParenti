global without sharing class CatalogEnrichmentRetryScheduler implements Schedulable {
    global void execute(SchedulableContext context) {
        if (!CatalogEnrichmentQueueable.isConfigured()) {
            return;
        }
        Datetime retryBefore = System.now().addHours(-20);
        List<Long> productIds = new List<Long>();
        for (Inventory__c inventory : [
            SELECT Inventory_Id__c
            FROM Inventory__c
            WHERE Inventory_Id__c != null
              AND Enriched_On__c = null
              AND (Last_Enrichment_Attempt__c = null OR Last_Enrichment_Attempt__c <= :retryBefore)
            ORDER BY Last_Enrichment_Attempt__c ASC NULLS FIRST
            LIMIT 2000
        ]) {
            productIds.add(Long.valueOf(inventory.Inventory_Id__c));
        }
        CatalogEnrichmentQueueable.enqueueIfConfigured(productIds, false);
    }
}
