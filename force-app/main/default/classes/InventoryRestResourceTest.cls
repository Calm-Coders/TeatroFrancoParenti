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
        String productId = '10228689876617';
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
    static void receiveInventory_prefersItalianActivityName() {
        assertActivityExternalName(
            10228689876618L,
            '"translations":[{"locale":"it","value":"TEATRO IT"},{"locale":"en","value":"THEATRE EN"}]',
            'TEATRO IT'
        );
    }

    @IsTest
    static void receiveInventory_fallsBackToEnglishActivityName() {
        assertActivityExternalName(
            10228689876619L,
            '"translations":[{"locale":"en","value":"THEATRE EN"}]',
            'THEATRE EN'
        );
    }

    @IsTest
    static void receiveInventory_prefersItalianInventoryNames() {
        assertInventoryTranslatedNames(
            10228689876620L,
            '"translations":[{"locale":"it","value":"EXTERNAL IT"},{"locale":"en","value":"EXTERNAL EN"}]',
            '"translations":[{"locale":"it","value":"INTERNAL IT"},{"locale":"en","value":"INTERNAL EN"}]',
            '"translations":[{"locale":"it","value":"SHORT IT"},{"locale":"en","value":"SHORT EN"}]',
            '"translations":[{"locale":"it","value":"DESCRIPTION IT"},{"locale":"en","value":"DESCRIPTION EN"}]',
            'EXTERNAL IT',
            'INTERNAL IT',
            'SHORT IT',
            'DESCRIPTION IT'
        );
    }

    @IsTest
    static void receiveInventory_fallsBackToEnglishInventoryNames() {
        assertInventoryTranslatedNames(
            10228689876621L,
            '"translations":[{"locale":"en","value":"EXTERNAL EN"}]',
            '"translations":[{"locale":"en","value":"INTERNAL EN"}]',
            '"translations":[{"locale":"en","value":"SHORT EN"}]',
            '"translations":[{"locale":"en","value":"DESCRIPTION EN"}]',
            'EXTERNAL EN',
            'INTERNAL EN',
            'SHORT EN',
            'DESCRIPTION EN'
        );
    }

    @IsTest
    static void receiveInventory_prefersItalianPerformanceText() {
        assertPerformanceTranslatedText(
            10228689876622L,
            10228689877622L,
            '"kindExternalName":{"translations":[{"locale":"it","value":"KIND IT"},{"locale":"en","value":"KIND EN"}]},' +
            '"spaceExternalName":{"translations":[{"locale":"it","value":"SPACE IT"},{"locale":"en","value":"SPACE EN"}]},' +
            '"siteExternalName":{"translations":[{"locale":"it","value":"SITE IT"},{"locale":"en","value":"SITE EN"}]},' +
            '"eventExternalName":{"translations":[{"locale":"it","value":"EVENT IT"},{"locale":"en","value":"EVENT EN"}]},' +
            '"externalName":{"translations":[{"locale":"it","value":"EXTERNAL IT"},{"locale":"en","value":"EXTERNAL EN"}]},' +
            '"internalName":{"translations":[{"locale":"it","value":"INTERNAL IT"},{"locale":"en","value":"INTERNAL EN"}]},' +
            '"externalShortName":{"translations":[{"locale":"it","value":"SHORT IT"},{"locale":"en","value":"SHORT EN"}]},' +
            '"externalDescription":{"translations":[{"locale":"it","value":null},{"locale":"en","value":null}]},' +
            '"internalDescription":{"translations":[{"locale":"it","value":null},{"locale":"en","value":null}]},' +
            '"nameAddOn":{"translations":[{"locale":"it","value":null},{"locale":"en","value":null}]}',
            new List<String>{
                'EXTERNAL IT', 'INTERNAL IT', 'SHORT IT', null, null, null,
                'KIND IT', 'SPACE IT', 'SITE IT', 'EVENT IT'
            }
        );
    }

    @IsTest
    static void receiveInventory_fallsBackToEnglishPerformanceText() {
        assertPerformanceTranslatedText(
            10228689876623L,
            10228689877623L,
            '"kindExternalName":{"translations":[{"locale":"en","value":"KIND EN"}]},' +
            '"spaceExternalName":{"translations":[{"locale":"en","value":"SPACE EN"}]},' +
            '"siteExternalName":{"translations":[{"locale":"en","value":"SITE EN"}]},' +
            '"eventExternalName":{"translations":[{"locale":"en","value":"EVENT EN"}]},' +
            '"externalName":{"translations":[{"locale":"en","value":"EXTERNAL EN"}]},' +
            '"internalName":{"translations":[{"locale":"en","value":"INTERNAL EN"}]},' +
            '"externalShortName":{"translations":[{"locale":"en","value":"SHORT EN"}]},' +
            '"externalDescription":{"translations":[{"locale":"en","value":"EXTERNAL DESCRIPTION EN"}]},' +
            '"internalDescription":{"translations":[{"locale":"en","value":"INTERNAL DESCRIPTION EN"}]},' +
            '"nameAddOn":{"translations":[{"locale":"en","value":"ADD ON EN"}]}',
            new List<String>{
                'EXTERNAL EN',
                'INTERNAL EN',
                'SHORT EN',
                'EXTERNAL DESCRIPTION EN',
                'INTERNAL DESCRIPTION EN',
                'ADD ON EN',
                'KIND EN',
                'SPACE EN',
                'SITE EN',
                'EVENT EN'
            }
        );
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

    private static void assertActivityExternalName(
        Long productId,
        String translationsJson,
        String expectedName
    ) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/inventories';
        req.resourcePath = '/v1/inventories';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"id":' + productId + ',"code":"ACTIVITY-TEST",' +
            '"productFamilyType":"SINGLE_ENTRY","productFamilySubType":"SIMPLE_TICKET",' +
            '"state":"RUNNING","externalName":{"translations":[{"locale":"it","value":"TEST EVENT"}]},' +
            '"event":{"activityId":10228689877000,"activityCode":"1",' +
            '"activityExternalName":{' + translationsJson + '},' +
            '"nameAddOn":{' + translationsJson + '},"performances":[]}}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        InventoryRestResource.receiveInventory();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        String productIdText = String.valueOf(productId);
        Inventory_Event__c eventRecord = [
            SELECT Activity_External_Name__c, Name_Add_On__c
            FROM Inventory_Event__c
            WHERE Inventory__r.Inventory_Id__c = :productIdText
            LIMIT 1
        ];
        System.assertEquals(expectedName, eventRecord.Activity_External_Name__c);
        System.assertEquals(expectedName, eventRecord.Name_Add_On__c);
    }

    private static void assertInventoryTranslatedNames(
        Long productId,
        String externalNameJson,
        String internalNameJson,
        String shortNameJson,
        String externalDescriptionJson,
        String expectedExternalName,
        String expectedInternalName,
        String expectedShortName,
        String expectedExternalDescription
    ) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/inventories';
        req.resourcePath = '/v1/inventories';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"id":' + productId + ',"code":"INVENTORY-NAME-TEST",' +
            '"productFamilyType":"SINGLE_ENTRY","productFamilySubType":"SIMPLE_TICKET",' +
            '"state":"RUNNING","externalName":{' + externalNameJson + '},' +
            '"internalName":{' + internalNameJson + '},' +
            '"shortName":{' + shortNameJson + '},' +
            '"externalDescription":{' + externalDescriptionJson + '}}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        InventoryRestResource.receiveInventory();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        String productIdText = String.valueOf(productId);
        Inventory__c inventory = [
            SELECT External_Name__c, Internal_Name__c, Short_Name__c, External_Description__c
            FROM Inventory__c
            WHERE Inventory_Id__c = :productIdText
            LIMIT 1
        ];
        System.assertEquals(expectedExternalName, inventory.External_Name__c);
        System.assertEquals(expectedInternalName, inventory.Internal_Name__c);
        System.assertEquals(expectedShortName, inventory.Short_Name__c);
        System.assertEquals(expectedExternalDescription, inventory.External_Description__c);
    }

    private static void assertPerformanceTranslatedText(
        Long productId,
        Long performanceId,
        String performanceTextJson,
        List<String> expectedValues
    ) {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/inventories';
        req.resourcePath = '/v1/inventories';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"id":' + productId + ',"code":"PERFORMANCE-TEXT-TEST",' +
            '"productFamilyType":"SINGLE_ENTRY","productFamilySubType":"SIMPLE_TICKET",' +
            '"state":"RUNNING","externalName":{"translations":[{"locale":"it","value":"TEST EVENT"}]},' +
            '"event":{"activityId":10228689878000,"activityCode":"1","performances":[{' +
            '"id":' + performanceId + ',"code":"PERFORMANCE-TEXT-TEST",' + performanceTextJson + '}]}}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        InventoryRestResource.receiveInventory();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        String performanceIdText = String.valueOf(performanceId);
        Performance__c performance = [
            SELECT External_Name__c, Internal_Name__c, External_Short_Name__c,
                   External_Description__c, Internal_Description__c, Name_Add_On__c,
                   Kind_External_Name__c, Space_External_Name__c, Site_External_Name__c,
                   Event_External_Name__c
            FROM Performance__c
            WHERE Performance_Id__c = :performanceIdText
            LIMIT 1
        ];
        System.assertEquals(expectedValues[0], performance.External_Name__c);
        System.assertEquals(expectedValues[1], performance.Internal_Name__c);
        System.assertEquals(expectedValues[2], performance.External_Short_Name__c);
        System.assertEquals(expectedValues[3], performance.External_Description__c);
        System.assertEquals(expectedValues[4], performance.Internal_Description__c);
        System.assertEquals(expectedValues[5], performance.Name_Add_On__c);
        System.assertEquals(expectedValues[6], performance.Kind_External_Name__c);
        System.assertEquals(expectedValues[7], performance.Space_External_Name__c);
        System.assertEquals(expectedValues[8], performance.Site_External_Name__c);
        System.assertEquals(expectedValues[9], performance.Event_External_Name__c);
    }
}
