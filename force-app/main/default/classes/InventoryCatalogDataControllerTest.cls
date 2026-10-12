@IsTest
private class InventoryCatalogDataControllerTest {
    private static final Long PRODUCT_ID = 10228687284447L;

    @IsTest
    static void getsFreshCatalogData() {
        Inventory__c inventory = createInventory(PRODUCT_ID);
        enableCatalogAccess();
        Test.setMock(HttpCalloutMock.class, new ResolveMock());

        Test.startTest();
        String responseBody = InventoryCatalogDataController.getCatalogData(inventory.Id);
        Test.stopTest();

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> products = (List<Object>) response.get('order');
        System.assertEquals(1, products.size());
        System.assertEquals(true, ((Map<String, Object>) products[0]).get('found'));
        Map<String, Object> applyResult = (Map<String, Object>) response.get('_salesforceApplyResult');
        System.assertEquals(Decimal.valueOf('1'), applyResult.get('inventoriesUpdated'));
        System.assertEquals(0, ((List<Object>) applyResult.get('errors')).size());
        System.assertEquals(String.valueOf(inventory.Id), response.get('_salesforceInventoryRecordId'));
        Inventory__c updatedInventory = [
            SELECT Catalog_Name_IT__c, Enrichment_Status__c, Enriched_On__c
            FROM Inventory__c
            WHERE Id = :inventory.Id
        ];
        System.assertEquals('Catalog product', updatedInventory.Catalog_Name_IT__c);
        System.assertEquals('Success', updatedInventory.Enrichment_Status__c);
        System.assertNotEquals(null, updatedInventory.Enriched_On__c);
    }

    @IsTest
    static void getsCatalogDataFromInventoryEventParent() {
        Inventory__c inventory = createInventory(PRODUCT_ID);
        Inventory_Event__c inventoryEvent = new Inventory_Event__c(
            Name = 'Catalog event test',
            Inventory__c = inventory.Id
        );
        insert inventoryEvent;
        enableCatalogAccess();
        Test.setMock(HttpCalloutMock.class, new ResolveMock());

        Test.startTest();
        String responseBody = InventoryCatalogDataController.getCatalogData(inventoryEvent.Id);
        Test.stopTest();

        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        System.assertEquals(true, ((Map<String, Object>) ((List<Object>) response.get('order'))[0]).get('found'));
        Inventory__c updatedInventory = [
            SELECT Enrichment_Status__c
            FROM Inventory__c
            WHERE Id = :inventory.Id
        ];
        System.assertEquals('Success', updatedInventory.Enrichment_Status__c);
    }

    @IsTest
    static void rejectsInventoryWithoutProductId() {
        Inventory__c inventory = createInventory(null);

        Boolean errorThrown = false;
        try {
            InventoryCatalogDataController.getCatalogData(inventory.Id);
        } catch (AuraHandledException error) {
            errorThrown = true;
            System.assert(error.getMessage().contains('Inventory Id is required'));
        }
        System.assert(errorThrown, 'Expected a missing Inventory Id error.');
    }

    @IsTest
    static void rejectsRequestWhenCatalogAccessIsDisabled() {
        Inventory__c inventory = createInventory(PRODUCT_ID);

        Boolean errorThrown = false;
        try {
            InventoryCatalogDataController.getCatalogData(inventory.Id);
        } catch (AuraHandledException error) {
            errorThrown = true;
            System.assert(error.getMessage().contains('Catalog access is not enabled'));
        }
        System.assert(errorThrown, 'Expected a catalog configuration error.');
    }

    private static Inventory__c createInventory(Long productId) {
        Inventory__c inventory = new Inventory__c(Name = 'Catalog data test');
        if (productId != null) {
            Schema.DisplayType productIdType = Inventory__c.Inventory_Id__c.getDescribe().getType();
            if (productIdType == Schema.DisplayType.String) {
                inventory.put('Inventory_Id__c', String.valueOf(productId));
            } else {
                inventory.put('Inventory_Id__c', Decimal.valueOf(String.valueOf(productId)));
            }
        }
        insert inventory;
        return inventory;
    }

    private static void enableCatalogAccess() {
        insert new Catalog_Enrichment_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Enabled__c = true,
            Named_Credential__c = 'Unit_Test_Catalog',
            Endpoint_Path__c = '/catalog-products-resolve'
        );
    }

    private class ResolveMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('POST', request.getMethod());
            System.assertEquals(
                'callout:Unit_Test_Catalog/catalog-products-resolve',
                request.getEndpoint()
            );

            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
            System.assertEquals(true, body.get('forceRefresh'));
            System.assertEquals(
                Decimal.valueOf(String.valueOf(PRODUCT_ID)),
                ((List<Object>) body.get('productIds'))[0]
            );

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(JSON.serialize(new Map<String, Object>{
                'started' => '2026-09-21 10:19:40am',
                'order' => new List<Object>{
                    new Map<String, Object>{
                        'productId' => PRODUCT_ID,
                        'found' => true,
                        'code' => '0101',
                        'name_it' => 'Catalog product',
                        'performances' => new List<Object>(),
                        'ticketTypes' => new List<Object>(),
                        'advantages' => new List<Object>(),
                        'crossSellProductLinks' => new List<Object>()
                    }
                },
                'excectution' => '0.01 Mins'
            }));
            return response;
        }
    }
}
