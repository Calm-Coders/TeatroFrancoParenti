@IsTest
private class CatalogEnrichmentTest {
    private static final Long PRODUCT_ID = 10228676772860L;
    private static final Long PERFORMANCE_ID = 10228676773179L;

    @IsTest
    static void serviceMapsProductActivityAndPerformance() {
        TestData data = createTestData(PRODUCT_ID, PERFORMANCE_ID);
        Map<String, Object> response = responsePayload(PRODUCT_ID, PERFORMANCE_ID, true);

        Test.startTest();
        CatalogEnrichmentService.Result result = CatalogEnrichmentService.applyResponse(response);
        Test.stopTest();

        System.assertEquals(1, result.received);
        System.assertEquals(1, result.found);
        System.assertEquals(1, result.inventoriesUpdated);
        System.assertEquals(1, result.eventsUpdated);
        System.assertEquals(1, result.performancesUpdated);
        System.assertEquals(1, result.salesChannelsUpdated);
        System.assertEquals(2, result.salePeriodsUpdated);
        System.assertEquals(2, result.salePeriodAudiencesUpdated);
        System.assertEquals(1, result.salePeriodSeatCategoriesUpdated);
        System.assertEquals(0, result.errors.size());

        Inventory__c inventory = [
            SELECT Catalog_Name_IT__c, Catalog_Name_EN__c, Season_Id__c, Season_Code__c,
                   Season_Name__c, Season_Start__c, Season_End__c, Product_Type_Id__c,
                   Product_Type_Name__c, Ticket_Types__c, Product_Advantages__c,
                   Enrichment_Status__c, Enriched_On__c, Enrichment_Error__c
            FROM Inventory__c
            WHERE Id = :data.inventoryId
        ];
        System.assertEquals('NAPOLI NOBILISSIMA', inventory.Catalog_Name_IT__c);
        System.assertEquals('10228635444462', inventory.Season_Id__c);
        System.assertEquals('2526', inventory.Season_Code__c);
        System.assertEquals('STAGIONE 25-26', inventory.Season_Name__c);
        System.assertEquals(Date.newInstance(2025, 6, 1), inventory.Season_Start__c);
        System.assertEquals(Decimal.valueOf('10228687303720'), inventory.Product_Type_Id__c);
        System.assertEquals('ABBONAMENTI E CARD', inventory.Product_Type_Name__c);
        System.assert(inventory.Ticket_Types__c.contains('INTERO'));
        System.assert(inventory.Product_Advantages__c.contains('RID50'));
        System.assertEquals('Success', inventory.Enrichment_Status__c);
        System.assertNotEquals(null, inventory.Enriched_On__c);
        System.assertEquals(null, inventory.Enrichment_Error__c);

        Inventory_Event__c eventRecord = [
            SELECT Activity_Id__c, Activity_Code__c, Activity_Type__c,
                   Activity_Name_IT__c, Activity_Name_EN__c
            FROM Inventory_Event__c
            WHERE Id = :data.eventId
        ];
        System.assertEquals(Decimal.valueOf('10228635444869'), eventRecord.Activity_Id__c);
        System.assertEquals('TEATRO', eventRecord.Activity_Name_IT__c);

        Performance__c performance = [
            SELECT Code__c, Start__c, Space_Code__c, Site_Code__c,
                   Site_Name_IT__c, Space_Name_IT__c, Physical_Configuration_Name__c,
                   Logical_Configuration_Name__c, Rate_Type_Name__c, Tariff_Legend__c
            FROM Performance__c
            WHERE Id = :data.performanceRecordId
        ];
        System.assertEquals('Teatro Franco Parenti', performance.Site_Name_IT__c);
        System.assertEquals('SALA GRANDE', performance.Space_Name_IT__c);
        System.assertEquals('01 - SALA GRANDE', performance.Physical_Configuration_Name__c);
        System.assertEquals('TEATRO', performance.Rate_Type_Name__c);
        System.assert(performance.Tariff_Legend__c.contains('INTERO'));
        System.assertEquals(1, [
            SELECT COUNT() FROM Sale_Period__c WHERE Inventory__c = :data.inventoryId
        ]);
        System.assertEquals(1, [
            SELECT COUNT() FROM Sale_Period__c WHERE Performance__c = :data.performanceRecordId
        ]);
        System.assertEquals(2, [SELECT COUNT() FROM Sale_Period_Audience__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Sale_Period_Seat_Category__c]);
    }

    @IsTest
    static void serviceUsesNestedApiVenueAndEventShape() {
        TestData data = createTestData(PRODUCT_ID, PERFORMANCE_ID);
        Map<String, Object> response = responsePayload(PRODUCT_ID, PERFORMANCE_ID, true);
        Map<String, Object> product = (Map<String, Object>) ((List<Object>) response.get('order'))[0];
        Map<String, Object> activity = (Map<String, Object>) product.remove('activity');
        List<Object> performances = (List<Object>) product.remove('performances');
        Map<String, Object> performancePayload = (Map<String, Object>) performances[0];
        performancePayload.put('performanceId', performancePayload.remove('id'));
        performancePayload.remove('siteCode');
        performancePayload.remove('spaceCode');
        performancePayload.remove('siteName_it');
        performancePayload.remove('siteName_en');
        performancePayload.remove('spaceName_it');
        performancePayload.remove('spaceName_en');
        performancePayload.put('site', new Map<String, Object>{
            'id' => 10228544852613L,
            'code' => '1',
            'name' => 'Teatro Franco Parenti',
            'town' => 'Milano',
            'address' => 'Via Pier Lombardo 14, Milano'
        });
        performancePayload.put('space', new Map<String, Object>{
            'id' => 10228544852816L,
            'code' => 'GRANDE',
            'name' => 'SALA GRANDE'
        });
        ((Map<String, Object>) performancePayload.get('physicalConfiguration')).put('id', 10228544670213L);
        ((Map<String, Object>) performancePayload.get('logicalConfiguration')).put('id', 10228635451835L);
        ((Map<String, Object>) performancePayload.get('rateType')).put('id', 10228635445070L);
        ((Map<String, Object>) performancePayload.get('rateType')).put('code', '1');
        product.put('event', new Map<String, Object>{
            'activity' => activity,
            'performances' => performances
        });

        CatalogEnrichmentService.Result result = CatalogEnrichmentService.applyResponse(response);

        System.assertEquals(1, result.performancesUpdated);
        System.assertEquals(1, result.performanceLocationsLinked);
        Performance__c performance = [
            SELECT Site_Id__c, Site_Code__c, Space_Id__c, Space_Code__c,
                   Site_Name_IT__c, Space_Name_IT__c, Location__c,
                   Physical_Configuration_Id__c, Logical_Configuration_Id__c,
                   Rate_Type_Id__c, Rate_Type_Code__c, Venue_Location__c
            FROM Performance__c
            WHERE Id = :data.performanceRecordId
        ];
        System.assertEquals(Decimal.valueOf('10228544852613'), performance.Site_Id__c);
        System.assertEquals('1', performance.Site_Code__c);
        System.assertEquals(Decimal.valueOf('10228544852816'), performance.Space_Id__c);
        System.assertEquals('GRANDE', performance.Space_Code__c);
        System.assertEquals('Teatro Franco Parenti', performance.Site_Name_IT__c);
        System.assertEquals('SALA GRANDE', performance.Space_Name_IT__c);
        System.assertEquals(Decimal.valueOf('10228544670213'), performance.Physical_Configuration_Id__c);
        System.assertEquals(Decimal.valueOf('10228635451835'), performance.Logical_Configuration_Id__c);
        System.assertEquals(Decimal.valueOf('10228635445070'), performance.Rate_Type_Id__c);
        System.assertEquals('1', performance.Rate_Type_Code__c);
        System.assert(performance.Location__c.contains('"site"'));
        System.assertNotEquals(null, performance.Venue_Location__c);

        Venue_Location__c location = [
            SELECT Site_Id__c, Space_Id__c, Town__c, Address__c
            FROM Venue_Location__c
            WHERE Id = :performance.Venue_Location__c
        ];
        System.assertEquals(Decimal.valueOf('10228544852613'), location.Site_Id__c);
        System.assertEquals(Decimal.valueOf('10228544852816'), location.Space_Id__c);
        System.assertEquals('Milano', location.Town__c);
        System.assertEquals('Via Pier Lombardo 14, Milano', location.Address__c);
    }

    @IsTest
    static void serviceKeepsDataWhenProductIsNotFound() {
        TestData data = createTestData(PRODUCT_ID, PERFORMANCE_ID);
        Map<String, Object> response = responsePayload(PRODUCT_ID, PERFORMANCE_ID, false);

        CatalogEnrichmentService.Result result = CatalogEnrichmentService.applyResponse(response);

        System.assertEquals(1, result.notFound);
        Inventory__c inventory = [
            SELECT Enrichment_Status__c, Enriched_On__c, Enrichment_Error__c
            FROM Inventory__c
            WHERE Id = :data.inventoryId
        ];
        System.assertEquals('Not Found', inventory.Enrichment_Status__c);
        System.assertEquals(null, inventory.Enriched_On__c);
        System.assertEquals('Product not found in current catalog', inventory.Enrichment_Error__c);
        System.assertEquals(1, [SELECT COUNT() FROM Performance__c WHERE Id = :data.performanceRecordId]);
    }

    @IsTest
    static void restResourceAppliesBootstrapPayload() {
        TestData data = createTestData(PRODUCT_ID, PERFORMANCE_ID);
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/v1/catalog-enrichment';
        request.resourcePath = '/v1/catalog-enrichment';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(JSON.serialize(responsePayload(PRODUCT_ID, PERFORMANCE_ID, true)));
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        CatalogEnrichmentRestResource.applyEnrichment();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(true, response.get('success'));
        System.assertEquals('Success', [
            SELECT Enrichment_Status__c FROM Inventory__c WHERE Id = :data.inventoryId
        ].Enrichment_Status__c);
        System.assertEquals(1, [
            SELECT COUNT() FROM Integration_Log__c
            WHERE Flow_Name__c = 'CatalogEnrichmentRestResource.apply'
              AND Is_Error__c = false
        ]);
    }

    @IsTest
    static void queueableCallsResolveApiAndWritesLog() {
        TestData data = createTestData(PRODUCT_ID, PERFORMANCE_ID);
        enableSetting();
        Test.setMock(HttpCalloutMock.class, new ResolveMock(PRODUCT_ID, PERFORMANCE_ID));

        Test.startTest();
        Id jobId = CatalogEnrichmentQueueable.enqueueIfConfigured(
            new List<Long>{ PRODUCT_ID, PRODUCT_ID },
            false
        );
        System.assertNotEquals(null, jobId);
        Test.stopTest();

        Inventory__c inventory = [
            SELECT Enrichment_Status__c, Catalog_Name_IT__c
            FROM Inventory__c
            WHERE Id = :data.inventoryId
        ];
        System.assertEquals('Success', inventory.Enrichment_Status__c);
        System.assertEquals('NAPOLI NOBILISSIMA', inventory.Catalog_Name_IT__c);
        Integration_Log__c logRecord = [
            SELECT Is_Error__c, Response_State__c, Request_Endpoint__c
            FROM Integration_Log__c
            WHERE Flow_Name__c = 'CatalogEnrichmentQueueable.resolveProducts'
            LIMIT 1
        ];
        System.assertEquals(false, logRecord.Is_Error__c);
        System.assertEquals('200', logRecord.Response_State__c);
        System.assertEquals('callout:Unit_Test_Catalog/catalog/products/resolve', logRecord.Request_Endpoint__c);
    }

    @IsTest
    static void queueableMarksErrorsAndSendsForceRefresh() {
        TestData data = createTestData(PRODUCT_ID, PERFORMANCE_ID);
        enableSetting();
        Test.setMock(HttpCalloutMock.class, new ErrorMock());

        Test.startTest();
        System.enqueueJob(new CatalogEnrichmentQueueable(new List<Long>{ PRODUCT_ID }, true));
        Test.stopTest();

        Inventory__c inventory = [
            SELECT Enrichment_Status__c, Last_Enrichment_Attempt__c, Enrichment_Error__c
            FROM Inventory__c
            WHERE Id = :data.inventoryId
        ];
        System.assertEquals('Error', inventory.Enrichment_Status__c);
        System.assertNotEquals(null, inventory.Last_Enrichment_Attempt__c);
        System.assert(inventory.Enrichment_Error__c.contains('HTTP 503'));
        Integration_Log__c logRecord = [
            SELECT Is_Error__c, Response_State__c
            FROM Integration_Log__c
            WHERE Flow_Name__c = 'CatalogEnrichmentQueueable.resolveProducts'
            LIMIT 1
        ];
        System.assertEquals(true, logRecord.Is_Error__c);
        System.assertEquals('503', logRecord.Response_State__c);
    }

    @IsTest
    static void restResourceRejectsMalformedJson() {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/v1/catalog-enrichment';
        request.resourcePath = '/v1/catalog-enrichment';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('not-json');
        RestContext.request = request;
        RestContext.response = new RestResponse();

        Test.startTest();
        CatalogEnrichmentRestResource.applyEnrichment();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        System.assertEquals(1, [
            SELECT COUNT() FROM Integration_Log__c
            WHERE Flow_Name__c = 'CatalogEnrichmentRestResource.apply'
              AND Is_Error__c = true
        ]);
    }

    @IsTest
    static void restResourceRejectsEmptyBody() {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/v1/catalog-enrichment';
        request.resourcePath = '/v1/catalog-enrichment';
        request.httpMethod = 'POST';
        RestContext.request = request;
        RestContext.response = new RestResponse();

        CatalogEnrichmentRestResource.applyEnrichment();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void schedulerEnqueuesPendingInventories() {
        TestData data = createTestData(PRODUCT_ID, PERFORMANCE_ID);
        enableSetting();
        Test.setMock(HttpCalloutMock.class, new ResolveMock(PRODUCT_ID, PERFORMANCE_ID));

        Test.startTest();
        new CatalogEnrichmentRetryScheduler().execute(null);
        Test.stopTest();

        System.assertEquals('Success', [
            SELECT Enrichment_Status__c FROM Inventory__c WHERE Id = :data.inventoryId
        ].Enrichment_Status__c);
    }

    @IsTest
    static void disabledSettingDoesNotEnqueue() {
        System.assertEquals(false, CatalogEnrichmentQueueable.isConfigured());
        System.assertEquals(null, CatalogEnrichmentQueueable.enqueueIfConfigured(
            new List<Long>{ PRODUCT_ID },
            false
        ));
    }

    private static void enableSetting() {
        insert new Catalog_Enrichment_Setting__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Enabled__c = true,
            Named_Credential__c = 'Unit_Test_Catalog',
            Endpoint_Path__c = '/catalog/products/resolve',
            Timeout_Milliseconds__c = 120000
        );
    }

    private static TestData createTestData(Long productId, Long performanceId) {
        Inventory__c inventory = new Inventory__c(
            Name = 'Test Inventory',
            Inventory_Id__c = Decimal.valueOf(String.valueOf(productId)),
            Enrichment_Status__c = 'Pending'
        );
        insert inventory;
        Inventory_Event__c eventRecord = new Inventory_Event__c(
            Name = 'Test Event',
            Inventory__c = inventory.Id
        );
        insert eventRecord;
        Performance__c performance = new Performance__c(
            Name = 'Test Performance',
            Inventory_Event__c = eventRecord.Id,
            Performance_Id__c = Decimal.valueOf(String.valueOf(performanceId))
        );
        insert performance;
        return new TestData(inventory.Id, eventRecord.Id, performance.Id);
    }

    private static Map<String, Object> responsePayload(Long productId, Long performanceId, Boolean found) {
        Map<String, Object> product = new Map<String, Object>{
            'productId' => productId,
            'found' => found
        };
        if (!found) {
            product.put('note', 'Product not found in current catalog');
            return new Map<String, Object>{ 'started' => '2026-07-23 12:10:25pm', 'order' => new List<Object>{ product } };
        }
        product.putAll(new Map<String, Object>{
            'code' => '0185',
            'productFamilyType' => 'SINGLE_ENTRY',
            'productFamilySubType' => 'SIMPLE_TICKET',
            'audienceType' => 'ALL',
            'state' => 'RUNNING',
            'waitingListAllowed' => false,
            'name_it' => 'NAPOLI NOBILISSIMA',
            'name_en' => 'NAPOLI NOBILISSIMA',
            'description_it' => '<p>Descrizione</p>',
            'description_en' => '<p>Description</p>',
            'season' => new Map<String, Object>{
                'id' => 10228635444462L,
                'code' => '2526',
                'name_it' => 'STAGIONE 25-26',
                'start' => '2025-06-01T00:00:00.000+02:00',
                'end' => '2026-09-27T00:00:00.000+02:00'
            },
            'productType' => new Map<String, Object>{
                'id' => 10228687303720L,
                'code' => '1',
                'name_it' => 'ABBONAMENTI E CARD'
            },
            'activity' => new Map<String, Object>{
                'id' => 10228635444869L,
                'code' => '1',
                'type' => 'LIVE_SPECT',
                'name_it' => 'TEATRO',
                'name_en' => 'THEATRE'
            },
            'ticketTypes' => new List<Object>{
                new Map<String, Object>{ 'id' => 10228635444778L, 'code' => 'I1', 'name' => 'INTERO + prev.', 'kind' => 'FULL' }
            },
            'salePeriods' => new List<Object>{
                new Map<String, Object>{
                    'start' => '2026-06-01T09:00:00.000+02:00',
                    'end' => '2026-07-23T20:45:00.000+02:00',
                    'salesChannelId' => 10228452598405L,
                    'salesChannelCode' => 'TS',
                    'salePossible' => true,
                    'reservationPossible' => false,
                    'quotationPossible' => false,
                    'postingResalePossible' => false,
                    'type' => 'STANDARD',
                    'audienceSubCatIds' => new List<Object>{ 10228635444778L }
                }
            },
            'performances' => new List<Object>{
                new Map<String, Object>{
                    'id' => performanceId,
                    'code' => '0185',
                    'start' => '2026-07-23T21:00:00.000+02:00',
                    'duration' => 5400,
                    'spaceCode' => 'GRANDE',
                    'siteCode' => '1',
                    'spaceName_it' => 'SALA GRANDE',
                    'spaceName_en' => 'SALA GRANDE',
                    'siteName_it' => 'Teatro Franco Parenti',
                    'siteName_en' => 'Teatro Franco Parenti',
                    'state' => 'RUNNING',
                    'physicalConfiguration' => new Map<String, Object>{ 'name' => '01 - SALA GRANDE' },
                    'logicalConfiguration' => new Map<String, Object>{ 'name' => 'SALA GRANDE' },
                    'rateType' => new Map<String, Object>{ 'name' => 'TEATRO' },
                    'salePeriods' => new List<Object>{
                        new Map<String, Object>{
                            'start' => '2026-06-01T09:00:00.000+02:00',
                            'end' => '2026-07-23T20:45:00.000+02:00',
                            'salesChannel' => new Map<String, Object>{
                                'id' => 10228452598405L,
                                'code' => 'TS',
                                'name_it' => 'Biglietteria online'
                            },
                            'salePossible' => true,
                            'type' => 'STANDARD',
                            'tariffs' => new List<Object>{
                                new Map<String, Object>{
                                    'id' => 10228635444778L,
                                    'code' => 'I1',
                                    'name_it' => 'INTERO + prev.',
                                    'kind' => 'FULL'
                                }
                            },
                            'seatCategories' => new List<Object>{
                                new Map<String, Object>{
                                    'id' => 10228635451937L,
                                    'code' => 'SA',
                                    'name_it' => 'SETTORE A'
                                }
                            }
                        }
                    }
                }
            },
            'advantages' => new List<Object>{
                new Map<String, Object>{ 'id' => 10228652653246L, 'code' => 'RID50', 'name_it' => 'Riduzione 50%' }
            },
            'crossSellProductLinks' => new List<Object>()
        });
        return new Map<String, Object>{
            'started' => '2026-07-23 12:10:25pm',
            'order' => new List<Object>{ product },
            'excectution' => '0.03 Mins'
        };
    }

    private class ResolveMock implements HttpCalloutMock {
        private Long productId;
        private Long performanceId;

        private ResolveMock(Long productId, Long performanceId) {
            this.productId = productId;
            this.performanceId = performanceId;
        }

        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('POST', request.getMethod());
            Map<String, Object> requestPayload = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
            System.assertEquals(1, ((List<Object>) requestPayload.get('productIds')).size());
            System.assertEquals(false, requestPayload.containsKey('forceRefresh'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody(JSON.serialize(responsePayload(productId, performanceId, true)));
            return response;
        }
    }

    private class ErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            Map<String, Object> requestPayload = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
            System.assertEquals(true, requestPayload.get('forceRefresh'));
            HttpResponse response = new HttpResponse();
            response.setStatusCode(503);
            response.setBody('{"error":"Temporarily unavailable"}');
            return response;
        }
    }

    private class TestData {
        private Id inventoryId;
        private Id eventId;
        private Id performanceRecordId;

        private TestData(Id inventoryId, Id eventId, Id performanceRecordId) {
            this.inventoryId = inventoryId;
            this.eventId = eventId;
            this.performanceRecordId = performanceRecordId;
        }
    }
}
