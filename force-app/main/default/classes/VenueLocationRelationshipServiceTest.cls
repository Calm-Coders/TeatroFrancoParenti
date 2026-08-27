@IsTest
private class VenueLocationRelationshipServiceTest {
    @IsTest
    static void storedJsonCreatesSharedLookupAndPreservesPerformances() {
        Inventory_Event__c eventRecord = createEvent(920001, 'Location Test');
        String locationJson = JSON.serialize(location('1', 'GRANDE', 'Teatro Franco Parenti', 'SALA GRANDE'));
        List<Performance__c> performances = new List<Performance__c>{
            new Performance__c(Name = 'L1', Inventory_Event__c = eventRecord.Id, Performance_Id__c = '930001', Location__c = locationJson),
            new Performance__c(Name = 'L2', Inventory_Event__c = eventRecord.Id, Performance_Id__c = '930002', Location__c = locationJson)
        };
        insert performances;

        VenueLocationRelationshipService.Stats stats =
            VenueLocationRelationshipService.syncStoredPerformances(performances);
        System.assertEquals(1, stats.locationsUpserted);
        System.assertEquals(2, stats.performancesLinked);
        System.assertEquals(1, [SELECT COUNT() FROM Venue_Location__c]);
        System.assertEquals(2, [SELECT COUNT() FROM Performance__c WHERE Venue_Location__c != null]);
        Id firstPerformanceId = performances[0].Id;
        Performance__c linked = [
            SELECT Id, Venue_Location__r.Location_Key__c, Venue_Location__r.Space_Name_IT__c
            FROM Performance__c WHERE Id = :firstPerformanceId
        ];
        System.assertEquals('1|GRANDE', linked.Venue_Location__r.Location_Key__c);
        System.assertEquals('SALA GRANDE', linked.Venue_Location__r.Space_Name_IT__c);
        System.assertEquals(2, [SELECT COUNT() FROM Performance__c], 'Performances must not be replaced.');
    }

    @IsTest
    static void enrichmentFlatVenueFieldsCreateLookup() {
        Inventory_Event__c eventRecord = createEvent(920002, 'Enrichment Location');
        Performance__c performance = new Performance__c(
            Name = 'EL1', Inventory_Event__c = eventRecord.Id, Performance_Id__c = '930003'
        );
        insert performance;
        Id inventoryId = [SELECT Inventory__c FROM Inventory_Event__c WHERE Id = :eventRecord.Id].Inventory__c;

        VenueLocationRelationshipService.Stats stats = VenueLocationRelationshipService.syncEnrichment(
            new Map<Id, Map<String, Object>>{
                inventoryId => new Map<String, Object>{
                    'performances' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 930003, 'siteCode' => '1', 'spaceCode' => 'TRE',
                            'siteName_it' => 'Teatro Franco Parenti', 'spaceName_it' => 'SALA TRE'
                        }
                    }
                }
            }
        );
        System.assertEquals(1, stats.locationsUpserted);
        System.assertEquals(
            '1|TRE',
            [SELECT Venue_Location__r.Location_Key__c FROM Performance__c WHERE Id = :performance.Id]
                .Venue_Location__r.Location_Key__c
        );
    }

    @IsTest
    static void enrichmentNestedVenueNodesAreAuthoritative() {
        Inventory_Event__c eventRecord = createEvent(920004, 'Nested Enrichment Location');
        Performance__c performance = new Performance__c(
            Name = 'NEL1', Inventory_Event__c = eventRecord.Id, Performance_Id__c = '930005'
        );
        insert performance;
        Id inventoryId = [SELECT Inventory__c FROM Inventory_Event__c WHERE Id = :eventRecord.Id].Inventory__c;

        VenueLocationRelationshipService.Stats stats = VenueLocationRelationshipService.syncEnrichment(
            new Map<Id, Map<String, Object>>{
                inventoryId => new Map<String, Object>{
                    'performances' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 930005,
                            'siteCode' => 'OLD',
                            'spaceCode' => 'OLD',
                            'site' => new Map<String, Object>{
                                'id' => 10228544852613L,
                                'code' => '1',
                                'name' => 'Teatro Franco Parenti',
                                'town' => 'Milano',
                                'address' => 'Via Pier Lombardo 14, Milano'
                            },
                            'space' => new Map<String, Object>{
                                'id' => 10228544852816L,
                                'code' => 'GRANDE',
                                'name' => 'SALA GRANDE'
                            }
                        }
                    }
                }
            }
        );

        System.assertEquals(1, stats.locationsUpserted);
        Venue_Location__c location = [
            SELECT Location_Key__c, Site_Id__c, Site_Code__c, Site_Name_IT__c,
                   Space_Id__c, Space_Code__c, Space_Name_IT__c, Town__c, Address__c, Raw_JSON__c
            FROM Venue_Location__c
            WHERE Location_Key__c = '1|GRANDE'
        ];
        System.assertEquals('10228544852613', location.Site_Id__c);
        System.assertEquals('10228544852816', location.Space_Id__c);
        System.assertEquals('Teatro Franco Parenti', location.Site_Name_IT__c);
        System.assertEquals('SALA GRANDE', location.Space_Name_IT__c);
        System.assertEquals('Milano', location.Town__c);
        System.assertEquals('Via Pier Lombardo 14, Milano', location.Address__c);
        System.assert(location.Raw_JSON__c.contains('"site"'));
        System.assertEquals(
            location.Id,
            [SELECT Venue_Location__c FROM Performance__c WHERE Id = :performance.Id].Venue_Location__c
        );
    }

    @IsTest
    static void backfillBatchLinksStoredLocation() {
        Inventory_Event__c eventRecord = createEvent(920003, 'Batch Location');
        insert new Performance__c(
            Name = 'BL1', Inventory_Event__c = eventRecord.Id, Performance_Id__c = '930004',
            Location__c = JSON.serialize(location('1', 'ROUGE', 'Teatro Franco Parenti', 'SALA ROUGE'))
        );
        Test.startTest();
        Id jobId = Database.executeBatch(new VenueLocationBackfillBatch(), 1);
        Test.stopTest();
        System.assertNotEquals(null, jobId);
        System.assertEquals(1, [SELECT COUNT() FROM Performance__c WHERE Venue_Location__c != null]);
    }

    private static Inventory_Event__c createEvent(Integer externalId, String label) {
        Inventory__c inventory = new Inventory__c(Name = label, Inventory_Id__c = String.valueOf(externalId));
        insert inventory;
        Inventory_Event__c eventRecord = new Inventory_Event__c(Name = label + ' Event', Inventory__c = inventory.Id);
        insert eventRecord;
        return eventRecord;
    }

    private static Map<String, Object> location(String siteCode, String spaceCode, String siteName, String spaceName) {
        return new Map<String, Object>{
            'siteCode' => siteCode,
            'spaceCode' => spaceCode,
            'siteExternalName' => translations(siteName),
            'spaceExternalName' => translations(spaceName)
        };
    }
    private static Map<String, Object> translations(String value) {
        return new Map<String, Object>{
            'translations' => new List<Object>{ new Map<String, Object>{ 'locale' => 'it', 'value' => value } }
        };
    }
}
