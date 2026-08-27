@IsTest
private class PackageLineRelationshipServiceTest {
    private static final Long OWNER_PRODUCT_ID = 10228691000001L;
    private static final Long TARGET_PRODUCT_ID = 10228691000002L;
    private static final Long FIRST_LINE_ID = 10228691000003L;
    private static final Long SECOND_LINE_ID = 10228691000004L;
    private static final Long AUDIENCE_ID = 10228691000005L;

    @IsTest
    static void inventoryApiCreatesLinksBackfillsAndRemovesStaleLines() {
        invokeInventoryApi(new List<Object>{ inventoryPayload(OWNER_PRODUCT_ID, 2) });

        Inventory__c ownerInventory = [
            SELECT Id FROM Inventory__c
            WHERE Inventory_Id__c = :String.valueOf(OWNER_PRODUCT_ID)
        ];
        Pack__c pack = [SELECT Id FROM Pack__c WHERE Inventory__c = :ownerInventory.Id];
        List<Package_Line__c> lines = [
            SELECT Id, Package_Line_Id__c, Sequence__c, Quantity__c, Optional__c,
                   Forced_Audience_Subcategory_Id__c, Forced_Audience_Sub_Category__c,
                   Target_Product_Id__c, Target_Product_Code__c, Target_Inventory__c,
                   Parent_Package_Line_Id__c, Parent_Package_Line__c, Raw_JSON__c
            FROM Package_Line__c
            WHERE Pack__c = :pack.Id
            ORDER BY Sequence__c
        ];
        System.assertEquals(2, lines.size());
        System.assertEquals(String.valueOf(FIRST_LINE_ID), lines[0].Package_Line_Id__c);
        System.assertEquals(1, lines[0].Sequence__c);
        System.assertEquals(2, lines[0].Quantity__c);
        System.assertEquals(false, lines[0].Optional__c);
        System.assertNotEquals(null, lines[0].Forced_Audience_Sub_Category__c);
        System.assertEquals(String.valueOf(TARGET_PRODUCT_ID), lines[0].Target_Product_Id__c);
        System.assertEquals('TARGET-01', lines[0].Target_Product_Code__c);
        System.assertEquals(null, lines[0].Target_Inventory__c);
        System.assertEquals(lines[0].Id, lines[1].Parent_Package_Line__c);
        System.assert(!lines[0].Raw_JSON__c.contains('performances'));

        invokeInventoryApi(new List<Object>{ inventoryPayload(TARGET_PRODUCT_ID, null) });
        Inventory__c targetInventory = [
            SELECT Id FROM Inventory__c
            WHERE Inventory_Id__c = :String.valueOf(TARGET_PRODUCT_ID)
        ];
        for (Package_Line__c line : [
            SELECT Target_Inventory__c FROM Package_Line__c WHERE Pack__c = :pack.Id
        ]) {
            System.assertEquals(targetInventory.Id, line.Target_Inventory__c);
        }

        invokeInventoryApi(new List<Object>{ inventoryPayload(OWNER_PRODUCT_ID, 2) });
        System.assertEquals(2, [
            SELECT COUNT() FROM Package_Line__c WHERE Pack__c = :pack.Id
        ]);

        invokeInventoryApi(new List<Object>{ inventoryPayload(OWNER_PRODUCT_ID, 1) });
        Package_Line__c remaining = [
            SELECT Package_Line_Id__c, Parent_Package_Line__c, Target_Inventory__c
            FROM Package_Line__c
            WHERE Pack__c = :pack.Id
        ];
        System.assertEquals(String.valueOf(FIRST_LINE_ID), remaining.Package_Line_Id__c);
        System.assertEquals(null, remaining.Parent_Package_Line__c);
        System.assertEquals(targetInventory.Id, remaining.Target_Inventory__c);
    }

    @IsTest
    static void batchBackfillsStoredJsonAndCountsInvalidPayloads() {
        Inventory__c owner = new Inventory__c(
            Name = 'Stored Package Owner',
            Inventory_Id__c = String.valueOf(OWNER_PRODUCT_ID + 100)
        );
        Inventory__c target = new Inventory__c(
            Name = 'Stored Target',
            Inventory_Id__c = String.valueOf(TARGET_PRODUCT_ID)
        );
        insert new List<Inventory__c>{ owner, target };
        Pack__c validPack = new Pack__c(
            Name = 'Stored Pack',
            Inventory__c = owner.Id,
            Package_Lines__c = JSON.serialize(new List<Object>{ linePayload(FIRST_LINE_ID, null) })
        );
        Pack__c invalidPack = new Pack__c(
            Name = 'Invalid Stored Pack',
            Inventory__c = owner.Id,
            Package_Lines__c = '{not-json'
        );
        insert new List<Pack__c>{ validPack, invalidPack };

        Test.startTest();
        Id jobId = Database.executeBatch(new PackageLineRelationshipBackfillBatch(), 50);
        Test.stopTest();

        AsyncApexJob job = [SELECT Status, NumberOfErrors FROM AsyncApexJob WHERE Id = :jobId];
        System.assertEquals('Completed', job.Status);
        System.assertEquals(0, job.NumberOfErrors);
        Package_Line__c line = [
            SELECT Pack__c, Target_Inventory__c, Forced_Audience_Sub_Category__c
            FROM Package_Line__c
            WHERE Pack__c = :validPack.Id
        ];
        System.assertEquals(target.Id, line.Target_Inventory__c);
        System.assertNotEquals(null, line.Forced_Audience_Sub_Category__c);
        System.assertEquals(0, [
            SELECT COUNT() FROM Package_Line__c WHERE Pack__c = :invalidPack.Id
        ]);
    }

    private static void invokeInventoryApi(List<Object> payload) {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/v1/inventories';
        request.resourcePath = '/v1/inventories';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(payload));
        RestContext.request = request;
        RestContext.response = new RestResponse();

        InventoryRestResource.receiveInventory();
        System.assertEquals(
            200,
            RestContext.response.statusCode,
            RestContext.response.responseBody == null
                ? 'No response body'
                : RestContext.response.responseBody.toString()
        );
    }

    private static Map<String, Object> inventoryPayload(Long productId, Integer packageLineCount) {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => productId,
            'code' => productId == OWNER_PRODUCT_ID ? 'PACK-01' : 'TARGET-01',
            'state' => 'RUNNING',
            'internalName' => new Map<String, Object>{
                'translations' => new List<Object>{
                    new Map<String, Object>{
                        'locale' => 'it',
                        'value' => productId == OWNER_PRODUCT_ID ? 'PACCHETTO TEST' : 'SPETTACOLO TEST'
                    }
                }
            }
        };
        if (packageLineCount != null) {
            List<Object> lines = new List<Object>{ linePayload(FIRST_LINE_ID, null) };
            if (packageLineCount > 1) {
                lines.add(linePayload(SECOND_LINE_ID, FIRST_LINE_ID));
            }
            payload.put('pack', new Map<String, Object>{
                'ticketPrintingMode' => 'TICKETS',
                'packageLine' => lines
            });
        }
        return payload;
    }

    private static Map<String, Object> linePayload(Long lineId, Long parentLineId) {
        return new Map<String, Object>{
            'packageLineId' => lineId,
            'quantity' => 2,
            'optional' => lineId == SECOND_LINE_ID,
            'forcedAudSubCatId' => AUDIENCE_ID,
            'rank' => lineId == FIRST_LINE_ID ? 1 : 2,
            'parentPackageLineId' => parentLineId,
            'product' => new Map<String, Object>{
                'id' => TARGET_PRODUCT_ID,
                'code' => 'TARGET-01',
                'event' => new Map<String, Object>{
                    'performances' => new List<Object>{
                        new Map<String, Object>{ 'id' => 10228691000006L }
                    }
                }
            }
        };
    }
}
