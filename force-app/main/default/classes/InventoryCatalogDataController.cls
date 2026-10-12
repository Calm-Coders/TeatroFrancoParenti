public with sharing class InventoryCatalogDataController {
    private static final Integer DEFAULT_TIMEOUT = 120000;

    @AuraEnabled
    public static String getCatalogData(Id recordId) {
        if (recordId == null) {
            throw handledException('An Inventory record is required.');
        }

        Id inventoryRecordId;
        if (recordId.getSObjectType() == Inventory__c.SObjectType) {
            inventoryRecordId = recordId;
        } else if (recordId.getSObjectType() == Inventory_Event__c.SObjectType) {
            List<Inventory_Event__c> inventoryEvents = [
                SELECT Inventory__c
                FROM Inventory_Event__c
                WHERE Id = :recordId
                LIMIT 1
            ];
            if (inventoryEvents.isEmpty() || inventoryEvents[0].Inventory__c == null) {
                throw handledException('The Inventory Event is not linked to an Inventory record.');
            }
            inventoryRecordId = inventoryEvents[0].Inventory__c;
        } else {
            throw handledException('This action is supported only for Inventory and Inventory Event records.');
        }

        List<Inventory__c> inventories = [
            SELECT Inventory_Id__c
            FROM Inventory__c
            WHERE Id = :inventoryRecordId
            LIMIT 1
        ];
        if (inventories.isEmpty()) {
            throw handledException('The Inventory record could not be found or is not accessible.');
        }

        Object rawProductId = inventories[0].get('Inventory_Id__c');
        if (rawProductId == null || String.isBlank(String.valueOf(rawProductId))) {
            throw handledException('Inventory Id is required before catalog data can be retrieved.');
        }
        Long productId;
        try {
            Decimal numericProductId = Decimal.valueOf(String.valueOf(rawProductId));
            productId = Long.valueOf(String.valueOf(numericProductId.setScale(0)));
        } catch (Exception error) {
            throw handledException('Inventory Id must contain a valid numeric product ID.');
        }

        if (!CatalogEnrichmentQueueable.isConfigured()) {
            throw handledException('Catalog access is not enabled or its Named Credential is not configured.');
        }
        Catalog_Enrichment_Setting__c setting = Catalog_Enrichment_Setting__c.getOrgDefaults();

        HttpRequest request = new HttpRequest();
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setEndpoint('callout:' + setting.Named_Credential__c + normalizePath(setting.Endpoint_Path__c));
        request.setTimeout(
            setting.Timeout_Milliseconds__c == null
                ? DEFAULT_TIMEOUT
                : setting.Timeout_Milliseconds__c.intValue()
        );
        request.setBody(JSON.serialize(new Map<String, Object>{
            'productIds' => new List<Long>{ productId },
            'forceRefresh' => true
        }));

        HttpResponse response;
        try {
            response = new Http().send(request);
        } catch (Exception error) {
            throw handledException('The catalog request failed: ' + error.getMessage());
        }

        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw handledException(
                'The catalog returned HTTP ' + response.getStatusCode() + ': ' + response.getBody()
            );
        }

        Object rawResponse;
        try {
            rawResponse = JSON.deserializeUntyped(response.getBody());
        } catch (System.JSONException error) {
            throw handledException('The catalog returned an invalid JSON response.');
        }
        if (!(rawResponse instanceof Map<String, Object>)) {
            throw handledException('The catalog returned a JSON response that is not an object.');
        }
        Map<String, Object> responsePayload = (Map<String, Object>) rawResponse;

        CatalogEnrichmentService.Result applyResult;
        try {
            applyResult = CatalogEnrichmentService.applyResponse(responsePayload);
        } catch (Exception error) {
            throw handledException('Catalog data was retrieved but could not be applied to Salesforce: ' + error.getMessage());
        }
        responsePayload.put('_salesforceApplyResult', applyResult.toMap());
        responsePayload.put('_salesforceInventoryRecordId', inventoryRecordId);
        return JSON.serialize(responsePayload);
    }

    private static String normalizePath(String path) {
        if (String.isBlank(path)) {
            return '/catalog-products-resolve';
        }
        return path.startsWith('/') ? path : '/' + path;
    }

    private static AuraHandledException handledException(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
