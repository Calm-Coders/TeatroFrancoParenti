@IsTest
private class SalePeriodRelationshipServiceTest {
    @IsTest
    static void inventoryApiCreatesRelationalSalePeriodsAndRefreshesThem() {
        invokeInventoryApi(payload(true));

        String productId = '10228689876699';
        Inventory__c inventory = [
            SELECT Id FROM Inventory__c WHERE Inventory_Id__c = :productId LIMIT 1
        ];
        Performance__c performance = [
            SELECT Id FROM Performance__c
            WHERE Inventory_Event__r.Inventory__c = :inventory.Id LIMIT 1
        ];
        System.assertEquals(1, [
            SELECT COUNT() FROM Sale_Period__c WHERE Inventory__c = :inventory.Id
        ]);
        System.assertEquals(1, [
            SELECT COUNT() FROM Sale_Period__c WHERE Performance__c = :performance.Id
        ]);
        System.assertEquals(1, [SELECT COUNT() FROM Sales_Channel__c]);
        System.assertEquals(4, [SELECT COUNT() FROM Sale_Period_Audience__c]);
        System.assertEquals(2, [SELECT COUNT() FROM Sale_Period_Seat_Category__c]);

        Sale_Period__c performancePeriod = [
            SELECT Parent_Type__c, Sales_Channel__r.Code__c, Sale_Possible__c,
                   Reservation_Possible__c
            FROM Sale_Period__c WHERE Performance__c = :performance.Id LIMIT 1
        ];
        System.assertEquals('Performance', performancePeriod.Parent_Type__c);
        System.assertEquals('TS', performancePeriod.Sales_Channel__r.Code__c);
        System.assertEquals(true, performancePeriod.Sale_Possible__c);
        System.assertEquals(false, performancePeriod.Reservation_Possible__c);

        invokeInventoryApi(payload(false));
        System.assertEquals(0, [
            SELECT COUNT() FROM Sale_Period__c WHERE Inventory__c = :inventory.Id
        ]);
        System.assertEquals(1, [
            SELECT COUNT() FROM Sale_Period__c
            WHERE Performance__r.Inventory_Event__r.Inventory__c = :inventory.Id
        ]);
        System.assertEquals(0, [SELECT COUNT() FROM Sale_Period_Audience__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Sale_Period_Seat_Category__c]);
    }

    private static void invokeInventoryApi(Map<String, Object> product) {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/v1/inventories';
        request.resourcePath = '/v1/inventories';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(product));
        RestContext.request = request;
        RestContext.response = new RestResponse();
        InventoryRestResource.receiveInventory();
        System.assertEquals(
            200,
            RestContext.response.statusCode,
            RestContext.response.responseBody == null
                ? 'No response body' : RestContext.response.responseBody.toString()
        );
    }

    private static Map<String, Object> payload(Boolean includeRestrictions) {
        List<Object> audienceIds = includeRestrictions
            ? new List<Object>{ 10228635444778L, 10228635444793L }
            : new List<Object>();
        List<Object> seatIds = includeRestrictions
            ? new List<Object>{ 10228635451937L, 10228635451938L }
            : new List<Object>();
        List<Object> productPeriods = includeRestrictions
            ? new List<Object>{ salePeriod(audienceIds, new List<Object>()) }
            : new List<Object>();
        return new Map<String, Object>{
            'id' => 10228689876699L,
            'code' => 'SPTEST',
            'productFamilyType' => 'SINGLE_ENTRY',
            'productFamilySubType' => 'SIMPLE_TICKET',
            'state' => 'RUNNING',
            'salePeriods' => productPeriods,
            'event' => new Map<String, Object>{
                'activityId' => 10228635444869L,
                'activityCode' => '1',
                'activityType' => 'LIVE_SPECT',
                'performances' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 10228689876700L,
                        'code' => 'SPTEST',
                        'start' => '2026-08-06T20:00:00.000+02:00',
                        'salePeriods' => new List<Object>{ salePeriod(audienceIds, seatIds) }
                    }
                }
            }
        };
    }

    private static Map<String, Object> salePeriod(
        List<Object> audienceIds,
        List<Object> seatIds
    ) {
        return new Map<String, Object>{
            'start' => '2026-06-25T09:00:00.000+02:00',
            'end' => '2026-08-06T19:45:00.000+02:00',
            'salesChannelId' => 10228452598405L,
            'salesChannelCode' => 'TS',
            'reservationPossible' => false,
            'salePossible' => true,
            'quotationPossible' => false,
            'postingResalePossible' => false,
            'type' => 'STANDARD',
            'audienceSubCatIds' => audienceIds,
            'seatCategoryIds' => seatIds
        };
    }
}
