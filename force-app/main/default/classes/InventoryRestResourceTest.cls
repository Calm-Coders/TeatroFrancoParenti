@IsTest
private class InventoryRestResourceTest {
    @IsTest
    static void receiveInventory_acceptsPayloadList() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/inventory';
        req.resourcePath = '/v1/inventory';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '[{"id":10228321399304,"prevSeasonProductId":null,"code":"2010CIMM","productFamilyType":"SINGLE_ENTRY","productFamilySubType":"SIMPLE_TICKET","audienceType":"ALL","state":"RUNNING","logo":null,"smallImageUrl":null,"mediumImageUrl":null,"largeImageUrl":null,"detailURL":null,"vatCodeId":15251,"ticketModelId":466679292,"chargesTableId":null,"partnerContactNumber":null,"productTypeId":null,"allowQuestionnaire":false,"questionnaireId":null,"salePeriods":[],"saleCloseExceptions":[],"externalName":{"translations":[{"locale":"fr","value":"A Shape of Things to Come"}]},"internalName":{"translations":[{"locale":"fr","value":"A Shape of Things to Come"}]},"shortName":{"translations":[{"locale":"fr","value":"A Shape of Thin"}]},"externalDescription":{"translations":[{"locale":"fr","value":null}]},"optionAvailabilities":[],"crossSellProductLinks":[],"subTopicLinks":[],"productSocialNetworkLinks":[],"comfortVariableValues":[],"media":[],"event":{"activityId":10228317615239,"activityCode":"CI","activityType":"OTHER","timeTolerance":null,"minimumAge":null,"language":null,"nameAddOn":{"translations":[{"locale":"fr","value":null}]},"activityExternalName":{"translations":[{"locale":"fr","value":"Cinema"}]},"competitionTypeId":null,"alertRatio":20.000,"performances":[{"id":10228321401021,"code":"2010CIMM","physicalConfigurationId":null,"logicalConfigurationId":466680741,"saleConfigurationId":null,"rateTypeId":306159280,"rateTypeCode":null,"ratesTableId":858268731,"chargesTableId":null,"start":1723831200000,"duration":null,"spaceId":null,"spaceCode":null,"siteCode":null,"kind":null,"kindExternalName":null,"seatSelectionMode":null,"breaksQuantity":null,"state":null,"image":null,"venueImage":null,"logo":null,"logoImage":null,"forceNominativeTickets":null,"titling":null,"blockComparisonEnabled":false,"numbered":null,"alwaysAllowIsolatedSeats":false,"externalName":{"translations":[{"locale":"fr","value":"A Shape of Things to Come"}]},"internalName":{"translations":[{"locale":"fr","value":"A Shape of Things to Come"}]},"externalShortName":{"translations":[{"locale":"fr","value":"A Shape of Thin"}]},"nameAddOn":{"translations":[{"locale":"fr","value":null}]},"spaceExternalName":null,"siteExternalName":null,"location":null,"match":null,"eventExternalName":null,"externalDescription":{"translations":[{"locale":"fr","value":null}]},"internalDescription":{"translations":[{"locale":"fr","value":null}]},"saleCloseExceptions":[],"seatCategories":[],"prices":[{"institutionSeatCatId":112908204,"seatCatId":null,"audSubCatId":306159078,"amount":35000,"minQty":null,"maxQty":null,"priceLevelId":null,"chargesAmounts":null}],"charges":[],"comfortVariableValues":[],"performanceType":null,"visitLanguageCode":null,"maxSeatsPerOrder":null,"itemIds":[10228321401627],"performanceSocialNetworkLinks":[],"salePeriods":[]}]},"service":null,"goods":null,"pack":null,"seasonTicket":null,"transport":null,"pass":null,"membership":null,"hospitality":null,"minQuantity":null,"maxQuantity":null,"culturalContact":null,"waitingListAllowed":false,"partnerContactId":null}]'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        InventoryRestResource.receiveInventory();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(true, resp.get('success'));
        System.assertEquals(1, ((List<Object>) resp.get('recordIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('productIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('productCodes')).size());
        System.assertEquals(1, ((List<Object>) resp.get('productStates')).size());

        List<Inventory__c> insertedRecords = [
            SELECT Id, Name
            FROM Inventory__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(1, insertedRecords.size());
        System.assertEquals('2010CIMM', insertedRecords[0].Name);

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
