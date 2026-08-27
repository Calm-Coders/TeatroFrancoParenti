@IsTest
private class MembershipRelationshipServiceTest {
    private static final Long PRODUCT_ID = 10228689876621L;
    private static final Long ITEM_ID = 10228690726514L;
    private static final Long AUDIENCE_ID = 10228683504634L;
    private static final Long CHANNEL_ID = 10228452598405L;

    @IsTest
    static void inventoryApiCreatesReportableMembershipGraphWithoutDuplicates() {
        invokeInventoryApi(inventoryPayload(true));

        Membership__c membership = [
            SELECT Id, Inventory__c, Items__c
            FROM Membership__c
            WHERE Inventory__r.Inventory_Id__c = :Decimal.valueOf(String.valueOf(PRODUCT_ID))
        ];
        Membership_Item__c item = [
            SELECT Id, Membership__c, Item_Id__c, Name_IT__c, Relationship_Key__c,
                   Raw_JSON__c
            FROM Membership_Item__c
            WHERE Membership__c = :membership.Id
        ];
        Membership_Item_Price__c price = [
            SELECT Id, Membership_Item__c, Amount__c, Min_Quantity__c,
                   Max_Quantity__c, Audience_Subcategory_Id__c,
                   Audience_Sub_Category__c,
                   Audience_Sub_Category__r.Audience_Subcategory_Id__c,
                   Price_Key__c, Raw_JSON__c
            FROM Membership_Item_Price__c
            WHERE Membership_Item__c = :item.Id
        ];
        Sale_Period__c period = [
            SELECT Id, Membership_Item_Price__c, Parent_Type__c, Start__c, End__c,
                   Type__c, Sale_Possible__c, Reservation_Possible__c,
                   Sales_Channel__r.Channel_Id__c, Sales_Channel__r.Code__c
            FROM Sale_Period__c
            WHERE Membership_Item_Price__c = :price.Id
        ];
        Sale_Period_Audience__c restriction = [
            SELECT Audience_Subcategory_Id__c, Audience_Sub_Category__c,
                   Audience_Sub_Category__r.Audience_Subcategory_Id__c
            FROM Sale_Period_Audience__c
            WHERE Sale_Period__c = :period.Id
        ];

        System.assertEquals(membership.Id, item.Membership__c);
        System.assertEquals(Decimal.valueOf(String.valueOf(ITEM_ID)), item.Item_Id__c);
        System.assertEquals('Carta sociale', item.Name_IT__c);
        System.assert(item.Relationship_Key__c.contains(String.valueOf(ITEM_ID)));
        System.assert(!item.Raw_JSON__c.contains('itemPrices'));
        System.assertEquals(100, price.Amount__c);
        System.assertEquals(1, price.Min_Quantity__c);
        System.assertEquals(null, price.Max_Quantity__c);
        System.assertEquals(Decimal.valueOf(String.valueOf(AUDIENCE_ID)), price.Audience_Subcategory_Id__c);
        System.assertNotEquals(null, price.Audience_Sub_Category__c);
        System.assertEquals(
            Decimal.valueOf(String.valueOf(AUDIENCE_ID)),
            price.Audience_Sub_Category__r.Audience_Subcategory_Id__c
        );
        System.assert(!price.Raw_JSON__c.contains('salePeriods'));
        System.assertEquals('Membership Item Price', period.Parent_Type__c);
        System.assertNotEquals(null, period.Start__c);
        System.assertNotEquals(null, period.End__c);
        System.assertEquals('STANDARD', period.Type__c);
        System.assertEquals(true, period.Sale_Possible__c);
        System.assertEquals(false, period.Reservation_Possible__c);
        System.assertEquals(Decimal.valueOf(String.valueOf(CHANNEL_ID)), period.Sales_Channel__r.Channel_Id__c);
        System.assertEquals('TS', period.Sales_Channel__r.Code__c);
        System.assertNotEquals(null, restriction.Audience_Sub_Category__c);
        System.assertEquals(
            Decimal.valueOf(String.valueOf(AUDIENCE_ID)),
            restriction.Audience_Sub_Category__r.Audience_Subcategory_Id__c
        );

        invokeInventoryApi(inventoryPayload(true));
        System.assertEquals(1, [SELECT COUNT() FROM Membership_Item__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Membership_Item_Price__c]);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM Sale_Period__c
            WHERE Membership_Item_Price__c != null
        ]);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM Sale_Period_Audience__c
            WHERE Sale_Period__r.Membership_Item_Price__c != null
        ]);

        invokeInventoryApi(inventoryPayload(false));
        System.assertEquals(1, [SELECT COUNT() FROM Membership_Item__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Membership_Item_Price__c]);
        System.assertEquals(0, [
            SELECT COUNT()
            FROM Sale_Period__c
            WHERE Membership_Item_Price__c != null
        ]);
    }

    @IsTest
    static void removingMembershipDeletesItsRelationalSalePeriods() {
        invokeInventoryApi(inventoryPayload(true));
        Map<String, Object> withoutMembership = inventoryPayload(true);
        withoutMembership.remove('membership');
        invokeInventoryApi(withoutMembership);

        System.assertEquals(0, [SELECT COUNT() FROM Membership__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Membership_Item__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Membership_Item_Price__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Sale_Period__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Sale_Period_Audience__c]);
    }

    @IsTest
    static void backfillBatchNormalizesStoredLegacyItems() {
        Inventory__c inventory = new Inventory__c(Name = 'Legacy', Inventory_Id__c = 90001);
        insert inventory;
        Map<String, Object> legacyItem = new Map<String, Object>{
            'itemId' => 90002,
            'code' => 'LEGACY',
            'rank' => 3,
            'donationAmount' => 2500,
            'voucherMinAmount' => 1000,
            'externalName' => translated('Legacy membership item', 'Legacy membership item')
        };
        insert new Membership__c(
            Name = 'Legacy Membership',
            Inventory__c = inventory.Id,
            Items__c = JSON.serialize(new List<Object>{ legacyItem })
        );

        Test.startTest();
        Id jobId = Database.executeBatch(new MembershipRelationshipBackfillBatch(), 1);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        Membership_Item__c item = [
            SELECT Item_Id__c, Code__c, Rank__c, Donation_Amount__c,
                   Voucher_Min_Amount__c, Name_IT__c
            FROM Membership_Item__c
        ];
        System.assertEquals(90002, item.Item_Id__c);
        System.assertEquals('LEGACY', item.Code__c);
        System.assertEquals(3, item.Rank__c);
        System.assertEquals(25, item.Donation_Amount__c);
        System.assertEquals(10, item.Voucher_Min_Amount__c);
        System.assertEquals('Legacy membership item', item.Name_IT__c);
        System.assertEquals(0, [SELECT COUNT() FROM Membership_Item_Price__c]);
    }

    private static void invokeInventoryApi(Map<String, Object> payload) {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/v1/inventories';
        request.resourcePath = '/v1/inventories';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(new List<Object>{ payload }));
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

    private static Map<String, Object> inventoryPayload(Boolean withPrices) {
        Map<String, Object> item = new Map<String, Object>{
            'itemId' => ITEM_ID,
            'code' => 'SOCIAL',
            'externalName' => translated('Carta sociale', 'Social card'),
            'itemPrices' => withPrices
                ? new List<Object>{ membershipPrice() }
                : new List<Object>()
        };
        return new Map<String, Object>{
            'id' => PRODUCT_ID,
            'code' => 'SOCIAL-2027',
            'state' => 'RUNNING',
            'internalName' => translated('PARENTI SOCIAL CARD 2027', 'PARENTI SOCIAL CARD 2027'),
            'membership' => new Map<String, Object>{
                'validityRule' => 'PERIOD',
                'validityStartDate' => '2026-07-28T00:00:00.000+02:00',
                'validityEndDate' => '2027-07-31T00:00:00.000+02:00',
                'userDefineStartValidity' => false,
                'items' => new List<Object>{ item }
            }
        };
    }

    private static Map<String, Object> membershipPrice() {
        return new Map<String, Object>{
            'audSubCatId' => AUDIENCE_ID,
            'amount' => 10000,
            'minQty' => 1,
            'maxQty' => null,
            'salePeriods' => new List<Object>{
                new Map<String, Object>{
                    'audienceSubCatIds' => new List<Object>{ AUDIENCE_ID },
                    'type' => 'STANDARD',
                    'postingResalePossible' => false,
                    'quotationPossible' => false,
                    'salePossible' => true,
                    'reservationPossible' => false,
                    'endRelative' => 0,
                    'salesChannelCode' => 'TS',
                    'salesChannelId' => CHANNEL_ID,
                    'end' => '2999-12-31T23:59:00.000+01:00',
                    'start' => '2026-07-28T09:00:00.000+02:00'
                }
            }
        };
    }

    private static Map<String, Object> translated(String italian, String english) {
        return new Map<String, Object>{
            'translations' => new List<Object>{
                new Map<String, Object>{ 'locale' => 'it', 'value' => italian },
                new Map<String, Object>{ 'locale' => 'en', 'value' => english }
            }
        };
    }
}
