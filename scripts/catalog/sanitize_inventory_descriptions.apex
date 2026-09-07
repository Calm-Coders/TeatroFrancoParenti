List<Inventory__c> updates = new List<Inventory__c>();

for (Inventory__c inventory : [
    SELECT Id, External_Description__c, Catalog_Description_IT__c, Catalog_Description_EN__c
    FROM Inventory__c
]) {
    String externalDescription = SecuTixTranslationParser.plainText(
        inventory.External_Description__c,
        32768
    );
    String catalogDescriptionIt = SecuTixTranslationParser.plainText(
        inventory.Catalog_Description_IT__c,
        32768
    );
    String catalogDescriptionEn = SecuTixTranslationParser.plainText(
        inventory.Catalog_Description_EN__c,
        32768
    );

    if (
        externalDescription != inventory.External_Description__c ||
        catalogDescriptionIt != inventory.Catalog_Description_IT__c ||
        catalogDescriptionEn != inventory.Catalog_Description_EN__c
    ) {
        updates.add(new Inventory__c(
            Id = inventory.Id,
            External_Description__c = externalDescription,
            Catalog_Description_IT__c = catalogDescriptionIt,
            Catalog_Description_EN__c = catalogDescriptionEn
        ));
    }
}

if (!updates.isEmpty()) {
    update updates;
}

System.debug(LoggingLevel.INFO, 'SANITIZED_INVENTORY_RECORDS=' + updates.size());
