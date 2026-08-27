@IsTest
private class SeatCategoryRelationshipServiceTest {
    @IsTest
    static void storedJsonCreatesLookupsAndRemovesStaleLinksWithoutReplacingPerformance() {
        Inventory__c inventory = new Inventory__c(Name = 'Seat Test', Inventory_Id__c = '880001');
        insert inventory;
        Inventory_Event__c eventRecord = new Inventory_Event__c(Name = 'Seat Test Event', Inventory__c = inventory.Id);
        insert eventRecord;
        Performance__c performance = new Performance__c(
            Name = 'Seat Test Performance',
            Inventory_Event__c = eventRecord.Id,
            Performance_Id__c = '990001',
            Seat_Categories__c = JSON.serialize(new List<Object>{ category(101, 'A', 'SETTORE A'), category(102, 'B', 'SETTORE B') })
        );
        insert performance;

        SeatCategoryRelationshipService.Stats first =
            SeatCategoryRelationshipService.syncStoredPerformances(new List<Performance__c>{ performance });
        System.assertEquals(2, first.categoriesUpserted);
        System.assertEquals(2, first.linksUpserted);
        System.assertEquals(2, [SELECT COUNT() FROM Seat_Category__c]);
        System.assertEquals(2, [SELECT COUNT() FROM Performance_Seat_Category__c]);
        Performance_Seat_Category__c link = [
            SELECT Performance__c, Seat_Category__r.Seat_Category_Id__c
            FROM Performance_Seat_Category__c WHERE Seat_Category__r.Seat_Category_Id__c = '101' LIMIT 1
        ];
        System.assertEquals(performance.Id, link.Performance__c);

        performance.Seat_Categories__c = JSON.serialize(new List<Object>{ category(102, 'B', 'SETTORE B UPDATED') });
        update performance;
        SeatCategoryRelationshipService.Stats second =
            SeatCategoryRelationshipService.syncStoredPerformances(new List<Performance__c>{ performance });
        System.assertEquals(1, second.linksDeleted);
        System.assertEquals(1, [SELECT COUNT() FROM Performance_Seat_Category__c]);
        System.assertEquals(
            performance.Id,
            [SELECT Performance__c FROM Performance_Seat_Category__c LIMIT 1].Performance__c,
            'The Performance record must be preserved.'
        );
    }

    @IsTest
    static void enrichmentUpdatesExistingPerformanceRelationships() {
        Inventory__c inventory = new Inventory__c(Name = 'Enrichment Seat Test', Inventory_Id__c = '880002');
        insert inventory;
        Inventory_Event__c eventRecord = new Inventory_Event__c(Name = 'Event', Inventory__c = inventory.Id);
        insert eventRecord;
        Performance__c performance = new Performance__c(
            Name = 'Performance', Inventory_Event__c = eventRecord.Id, Performance_Id__c = '990002'
        );
        insert performance;

        Map<String, Object> performancePayload = new Map<String, Object>{
            'id' => 990002,
            'seatCategories' => new List<Object>{ category(201, 'C', 'PLATEA') }
        };
        SeatCategoryRelationshipService.Stats stats = SeatCategoryRelationshipService.syncEnrichment(
            new Map<Id, Map<String, Object>>{
                inventory.Id => new Map<String, Object>{ 'performances' => new List<Object>{ performancePayload } }
            }
        );
        System.assertEquals(1, stats.linksUpserted);
        System.assertEquals(performance.Id, [SELECT Performance__c FROM Performance_Seat_Category__c LIMIT 1].Performance__c);
    }

    @IsTest
    static void backfillBatchCreatesRelationshipsFromStoredJson() {
        Inventory__c inventory = new Inventory__c(Name = 'Batch Seat Test', Inventory_Id__c = '880003');
        insert inventory;
        Inventory_Event__c eventRecord = new Inventory_Event__c(Name = 'Batch Event', Inventory__c = inventory.Id);
        insert eventRecord;
        Performance__c performance = new Performance__c(
            Name = 'Batch Performance',
            Inventory_Event__c = eventRecord.Id,
            Performance_Id__c = '990003',
            Seat_Categories__c = JSON.serialize(new List<Object>{ category(301, 'D', 'GALLERIA') })
        );
        insert performance;

        Test.startTest();
        Id jobId = Database.executeBatch(new SeatCategoryBackfillBatch(), 1);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertEquals(1, [SELECT COUNT() FROM Seat_Category__c WHERE Seat_Category_Id__c = '301']);
        System.assertEquals(
            performance.Id,
            [SELECT Performance__c FROM Performance_Seat_Category__c LIMIT 1].Performance__c
        );
    }

    private static Map<String, Object> category(Integer idValue, String code, String name) {
        return new Map<String, Object>{
            'id' => idValue,
            'code' => code,
            'rank' => 1,
            'institutionCategoryId' => 501,
            'catNum' => code,
            'textColor' => 'FFFFFF',
            'bgColor' => '000000',
            'sameBlockRestrictionMode' => 'NONE',
            'preRequestLogicalSeatCatIds' => new List<Object>(),
            'externalName' => new Map<String, Object>{
                'translations' => new List<Object>{
                    new Map<String, Object>{ 'locale' => 'it', 'value' => name },
                    new Map<String, Object>{ 'locale' => 'en', 'value' => name }
                }
            }
        };
    }
}
