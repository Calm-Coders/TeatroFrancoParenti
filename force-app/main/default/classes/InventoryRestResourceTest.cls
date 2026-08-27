@IsTest
private class InventoryRestResourceTest {
    @IsTest
    static void receiveInventory_acceptsPayloadList() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/inventory';
        req.resourcePath = '/v1/inventory';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '[{"id":10228321399304,"prevSeasonProductId":null,"code":"2010CIMM","productFamilyType":"SINGLE_ENTRY","productFamilySubType":"SIMPLE_TICKET","audienceType":"ALL","state":"RUNNING","logo":null,"smallImageUrl":null,"mediumImageUrl":null,"largeImageUrl":null,"detailURL":null,"vatCodeId":15251,"ticketModelId":466679292,"chargesTableId":null,"partnerContactNumber":null,"productTypeId":null,"allowQuestionnaire":false,"questionnaireId":null,"salePeriods":[],"saleCloseExceptions":[],"externalName":{"translations":[{"locale":"fr","value":"A Shape of Things to Come"}]},"internalName":{"translations":[{"locale":"it","value":"ABBO LIBERO CONVENZIONATI 5 SPETTACOLI"},{"locale":"en","value":"ABBO LIBERO CONVENZIONATI 5 SPETTACOLI"}]},"shortName":{"translations":[{"locale":"fr","value":"A Shape of Thin"}]},"externalDescription":{"translations":[{"locale":"fr","value":null}]},"optionAvailabilities":[],"crossSellProductLinks":[],"subTopicLinks":[],"productSocialNetworkLinks":[],"comfortVariableValues":[],"media":[],"event":{"activityId":10228317615239,"activityCode":"CI","activityType":"OTHER","timeTolerance":null,"minimumAge":null,"language":null,"nameAddOn":{"translations":[{"locale":"fr","value":null}]},"activityExternalName":{"translations":[{"locale":"fr","value":"Cinema"}]},"competitionTypeId":null,"alertRatio":20.000,"performances":[{"id":10228321401021,"code":"2010CIMM","physicalConfigurationId":null,"logicalConfigurationId":466680741,"saleConfigurationId":null,"rateTypeId":306159280,"rateTypeCode":null,"ratesTableId":858268731,"chargesTableId":null,"start":1723831200000,"duration":null,"spaceId":null,"spaceCode":null,"siteCode":null,"kind":null,"kindExternalName":null,"seatSelectionMode":null,"breaksQuantity":null,"state":null,"image":null,"venueImage":null,"logo":null,"logoImage":null,"forceNominativeTickets":null,"titling":null,"blockComparisonEnabled":false,"numbered":null,"alwaysAllowIsolatedSeats":false,"externalName":{"translations":[{"locale":"fr","value":"A Shape of Things to Come"}]},"internalName":{"translations":[{"locale":"fr","value":"A Shape of Things to Come"}]},"externalShortName":{"translations":[{"locale":"fr","value":"A Shape of Thin"}]},"nameAddOn":{"translations":[{"locale":"fr","value":null}]},"spaceExternalName":null,"siteExternalName":null,"location":null,"match":null,"eventExternalName":null,"externalDescription":{"translations":[{"locale":"fr","value":null}]},"internalDescription":{"translations":[{"locale":"fr","value":null}]},"saleCloseExceptions":[],"seatCategories":[],"prices":[{"institutionSeatCatId":112908204,"seatCatId":null,"audSubCatId":306159078,"amount":35000,"minQty":null,"maxQty":null,"priceLevelId":null,"chargesAmounts":null}],"charges":[],"comfortVariableValues":[],"performanceType":null,"visitLanguageCode":null,"maxSeatsPerOrder":null,"itemIds":[10228321401627],"performanceSocialNetworkLinks":[],"salePeriods":[]}]},"service":null,"goods":null,"pack":null,"seasonTicket":null,"transport":null,"pass":null,"membership":null,"hospitality":null,"minQuantity":null,"maxQuantity":null,"culturalContact":null,"waitingListAllowed":false,"partnerContactId":null,"seasonId":"SEASON-2026"}]'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        InventoryRestResource.receiveInventory();
        Test.stopTest();

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(200, RestContext.response.statusCode, 'DEBUG server message: ' + resp.get('message'));
        System.assertEquals(true, resp.get('success'));
        System.assertEquals(1, ((List<Object>) resp.get('recordIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('productIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('productCodes')).size());
        System.assertEquals(1, ((List<Object>) resp.get('productStates')).size());

        List<Inventory__c> insertedRecords = [
            SELECT Id, Name, Season_Id__c
            FROM Inventory__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(1, insertedRecords.size());
        System.assertEquals('ABBO LIBERO CONVENZIONATI 5 SPETTACOLI', insertedRecords[0].Name);
        System.assertEquals('SEASON-2026', insertedRecords[0].Season_Id__c);

        List<Inventory_Event__c> insertedEventRecords = [
            SELECT Id, Name, Inventory__c
            FROM Inventory_Event__c
            WHERE Inventory__c = :insertedRecords[0].Id
            LIMIT 1
        ];
        System.assertEquals(1, insertedEventRecords.size());
        System.assertEquals('10228317615239', insertedEventRecords[0].Name);

        List<Performance__c> insertedPerformanceRecords = [
            SELECT Id, Name, Inventory_Event__c
            FROM Performance__c
            WHERE Inventory_Event__c = :insertedEventRecords[0].Id
            LIMIT 10
        ];
        System.assertEquals(1, insertedPerformanceRecords.size());
        System.assertEquals('2010CIMM', insertedPerformanceRecords[0].Name);

        Integration_Log__c logRec = [
            SELECT Flow_Name__c, Integration_Type__c, Is_Error__c, Request_Endpoint__c, Response_State__c
            FROM Integration_Log__c
            WHERE Flow_Name__c = 'InventoryRestResource.receiveInventory'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('Inbound', logRec.Integration_Type__c);
        System.assertEquals(false, logRec.Is_Error__c);
        System.assertEquals('/v1/inventory', logRec.Request_Endpoint__c);
        System.assertEquals('200', logRec.Response_State__c);
    }

    @IsTest
    static void receiveInventory_populatesSeasonMetadataFromInitialLoad() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/inventories';
        req.resourcePath = '/v1/inventories';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"id":10228689876617,"code":"0127","productFamilyType":"SINGLE_ENTRY",' +
            '"productFamilySubType":"SIMPLE_TICKET","state":"RUNNING",' +
            '"externalName":{"translations":[{"locale":"it","value":"TEST STAGIONE"}]},' +
            '"season":{"id":10228683117776,"code":"2627","name_it":"STAGIONE 26-27",' +
            '"start":"2026-06-01T00:00:00.000+02:00","end":"2027-07-31T00:00:00.000+02:00"}}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        InventoryRestResource.receiveInventory();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Decimal productId = Decimal.valueOf('10228689876617');
        Inventory__c inventory = [
            SELECT Season_Id__c, Season_Code__c, Season_Name__c, Season_Start__c, Season_End__c
            FROM Inventory__c
            WHERE Inventory_Id__c = :productId
            LIMIT 1
        ];
        System.assertEquals('10228683117776', inventory.Season_Id__c);
        System.assertEquals('2627', inventory.Season_Code__c);
        System.assertEquals('STAGIONE 26-27', inventory.Season_Name__c);
        System.assertEquals(Date.newInstance(2026, 6, 1), inventory.Season_Start__c);
        System.assertEquals(Date.newInstance(2027, 7, 31), inventory.Season_End__c);
    }

    @IsTest
    static void receiveInventory_rejectsInvalidJson() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/inventory';
        req.resourcePath = '/v1/inventory';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('not-json');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        InventoryRestResource.receiveInventory();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(false, resp.get('success'));
        System.assertEquals('Invalid JSON payload.', resp.get('message'));
    }
}
