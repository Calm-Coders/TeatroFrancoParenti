Map<Id, Map<String, Object>> productsByInventoryId = new Map<Id, Map<String, Object>>();
Integer invalidPayloads = 0;

for (Inventory__c inventory : [
    SELECT Id, Cross_Sell_Product_Links__c
    FROM Inventory__c
]) {
    if (String.isBlank(inventory.Cross_Sell_Product_Links__c)) continue;
    try {
        Object parsed = JSON.deserializeUntyped(inventory.Cross_Sell_Product_Links__c);
        if (!(parsed instanceof List<Object>)) continue;
        productsByInventoryId.put(
            inventory.Id,
            new Map<String, Object>{ 'crossSellProductLinks' => parsed }
        );
    } catch (Exception ignored) {
        invalidPayloads++;
    }
}

CrossSellProductRelationshipService.Stats stats =
    CrossSellProductRelationshipService.syncEnrichment(productsByInventoryId);

System.debug(LoggingLevel.ERROR, JSON.serialize(new Map<String, Object>{
    'inventoriesProcessed' => productsByInventoryId.size(),
    'invalidPayloads' => invalidPayloads,
    'linksUpserted' => stats.linksUpserted,
    'targetsLinked' => stats.targetsLinked,
    'linksDeleted' => stats.linksDeleted
}));
