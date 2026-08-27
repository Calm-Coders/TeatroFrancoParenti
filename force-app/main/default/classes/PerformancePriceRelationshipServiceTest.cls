@IsTest
private class PerformancePriceRelationshipServiceTest {
    @IsTest
    static void storedRawPricesCreateCompleteRelationshipsAndRemoveStaleRows() {
        Performance__c performance = createPerformance(910001, 'Raw Price');
        performance.Prices__c = JSON.serialize(new List<Object>{ rawPrice(101, 201, 34000, 4000) });
        performance.Tariff_Legend__c = JSON.serialize(new List<Object>{ tariff(201, 'I1', 'INTERO + prev.') });
        update performance;

        PerformancePriceRelationshipService.Stats first =
            PerformancePriceRelationshipService.syncStoredPerformances(new List<Performance__c>{ performance });

        System.assertEquals(1, first.pricesUpserted);
        System.assertEquals(1, first.priceChargesUpserted);
        Performance_Price__c price = [
            SELECT Performance__c, Amount__c, Seat_Category__r.Seat_Category_Id__c,
                   Audience_Sub_Category__r.Audience_Subcategory_Id__c,
                   Audience_Sub_Category__r.Name_IT__c
            FROM Performance_Price__c LIMIT 1
        ];
        System.assertEquals(performance.Id, price.Performance__c);
        System.assertEquals(340, price.Amount__c);
        System.assertEquals('101', price.Seat_Category__r.Seat_Category_Id__c);
        System.assertEquals('201', price.Audience_Sub_Category__r.Audience_Subcategory_Id__c);
        System.assertEquals('INTERO + prev.', price.Audience_Sub_Category__r.Name_IT__c);
        System.assertEquals(40, [SELECT Amount__c FROM Performance_Price_Charge__c LIMIT 1].Amount__c);

        performance.Prices__c = '[]';
        update performance;
        PerformancePriceRelationshipService.Stats second =
            PerformancePriceRelationshipService.syncStoredPerformances(new List<Performance__c>{ performance });
        System.assertEquals(1, second.pricesDeleted);
        System.assertEquals(0, [SELECT COUNT() FROM Performance_Price__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Performance_Price_Charge__c]);
        System.assertEquals(1, [SELECT COUNT() FROM Performance__c WHERE Id = :performance.Id]);
    }

    @IsTest
    static void enrichmentPriceGridCreatesNamedLookupsAndFormattedAmounts() {
        Performance__c performance = createPerformance(910002, 'Enrichment Price');
        insert new Seat_Category__c(
            Name = 'SETTORE A', Category_Key__c = '301', Seat_Category_Id__c = '301',
            Code__c = 'SA', Name_IT__c = 'SETTORE A'
        );
        Map<String, Object> priceGridRow = new Map<String, Object>{
            'seatCategory' => new Map<String, Object>{ 'id' => 301, 'code' => 'SA', 'name_it' => 'SETTORE A' },
            'tariff' => tariff(401, 'I3', 'UNDER 30'),
            'amount' => '€345.00',
            'minQty' => 1,
            'fees' => new List<Object>{
                new Map<String, Object>{ 'component' => 'PREV', 'amount' => '€45.00' }
            }
        };
        Id inventoryId = [
            SELECT Inventory_Event__r.Inventory__c FROM Performance__c WHERE Id = :performance.Id
        ].Inventory_Event__r.Inventory__c;
        PerformancePriceRelationshipService.Stats stats = PerformancePriceRelationshipService.syncEnrichment(
            new Map<Id, Map<String, Object>>{
                inventoryId => new Map<String, Object>{
                    'ticketTypes' => new List<Object>{ tariff(401, 'I3', 'UNDER 30') },
                    'performances' => new List<Object>{
                        new Map<String, Object>{ 'id' => 910002, 'priceGrid' => new List<Object>{ priceGridRow } }
                    }
                }
            }
        );
        System.assertEquals(1, stats.pricesUpserted);
        System.assertEquals(1, stats.priceChargesUpserted);
        Performance_Price__c price = [
            SELECT Amount__c, Seat_Category__r.Code__c, Audience_Sub_Category__r.Code__c
            FROM Performance_Price__c LIMIT 1
        ];
        System.assertEquals(345, price.Amount__c);
        System.assertEquals('SA', price.Seat_Category__r.Code__c);
        System.assertEquals('I3', price.Audience_Sub_Category__r.Code__c);
        Performance_Price_Charge__c fee = [
            SELECT Amount__c, Charge_Component__r.Code__c FROM Performance_Price_Charge__c LIMIT 1
        ];
        System.assertEquals(45, fee.Amount__c);
        System.assertEquals('PREV', fee.Charge_Component__r.Code__c);
    }

    @IsTest
    static void batchesCoverStoredPricesAndSalePeriodAudienceLookups() {
        Performance__c performance = createPerformance(910003, 'Batch Price');
        performance.Prices__c = JSON.serialize(new List<Object>{ rawPrice(501, 601, 25000, 3000) });
        update performance;
        Id inventoryId = performance.Inventory_Event__r.Inventory__c;
        Inventory__c inventory = [SELECT Id FROM Inventory__c WHERE Id = :inventoryId];
        Sale_Period__c period = new Sale_Period__c(
            Relationship_Key__c = 'TEST-PERIOD', Inventory__c = inventory.Id, Parent_Type__c = 'Inventory'
        );
        insert period;
        insert new Sale_Period_Audience__c(
            Sale_Period__c = period.Id, Audience_Subcategory_Id__c = '601',
            Code__c = 'I5', Name_IT__c = 'OVER 65', Kind__c = 'FULL'
        );

        Test.startTest();
        Id priceJob = Database.executeBatch(new PerformancePriceBackfillBatch(), 1);
        Id audienceJob = Database.executeBatch(new AudienceRelationshipBackfillBatch(), 1);
        Test.stopTest();

        System.assertNotEquals(null, priceJob);
        System.assertNotEquals(null, audienceJob);
        System.assertEquals(1, [SELECT COUNT() FROM Performance_Price__c]);
        Sale_Period_Audience__c restriction = [
            SELECT Audience_Sub_Category__c, Audience_Sub_Category__r.Audience_Subcategory_Id__c
            FROM Sale_Period_Audience__c LIMIT 1
        ];
        System.assertNotEquals(null, restriction.Audience_Sub_Category__c);
        System.assertEquals('601', restriction.Audience_Sub_Category__r.Audience_Subcategory_Id__c);
    }

    private static Performance__c createPerformance(Integer externalId, String label) {
        Inventory__c inventory = new Inventory__c(Name = label, Inventory_Id__c = String.valueOf(externalId + 10000));
        insert inventory;
        Inventory_Event__c eventRecord = new Inventory_Event__c(Name = label + ' Event', Inventory__c = inventory.Id);
        insert eventRecord;
        Performance__c performance = new Performance__c(
            Name = label, Inventory_Event__c = eventRecord.Id, Performance_Id__c = String.valueOf(externalId)
        );
        insert performance;
        return [
            SELECT Id, Inventory_Event__c, Inventory_Event__r.Inventory__c,
                   Performance_Id__c, Prices__c, Tariff_Legend__c
            FROM Performance__c WHERE Id = :performance.Id
        ];
    }

    private static Map<String, Object> rawPrice(Integer seatId, Integer audienceId, Integer amount, Integer charge) {
        return new Map<String, Object>{
            'institutionSeatCatId' => seatId + 1000,
            'seatCatId' => seatId,
            'audSubCatId' => audienceId,
            'amount' => amount,
            'minQty' => 1,
            'maxQty' => null,
            'chargesAmounts' => new List<Object>{
                new Map<String, Object>{ 'chargesId' => 701, 'amount' => charge }
            }
        };
    }

    private static Map<String, Object> tariff(Integer idValue, String code, String nameValue) {
        return new Map<String, Object>{
            'id' => idValue, 'code' => code, 'name' => nameValue,
            'name_it' => nameValue, 'kind' => 'FULL', 'rank' => 1
        };
    }
}
