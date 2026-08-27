@IsTest
private class SeasonTicketRelationshipServiceTest {
    private static final Long OWNER_PRODUCT_ID = 10228690000001L;
    private static final Long TARGET_PRODUCT_ID = 10228690000002L;
    private static final Long LINE_ID = 10228690000003L;

    @IsTest
    static void inventoryApiCreatesAndBackfillsRelationshipsWithoutDuplicates() {
        invokeInventoryApi(new List<Object>{ inventoryPayload(OWNER_PRODUCT_ID, true) });

        Inventory__c ownerInventory = [
            SELECT Id FROM Inventory__c
            WHERE Inventory_Id__c = :String.valueOf(OWNER_PRODUCT_ID)
        ];
        Season_Ticket__c seasonTicket = [
            SELECT Id FROM Season_Ticket__c WHERE Inventory__c = :ownerInventory.Id
        ];
        Season_Ticket_Subject__c subject = [
            SELECT Id, Subject_Code__c, Name_IT__c
            FROM Season_Ticket_Subject__c
            WHERE Season_Ticket__c = :seasonTicket.Id
        ];
        Season_Ticket_Line__c lineBeforeTarget = [
            SELECT Id, Subject__c, Target_Product_Id__c, Target_Inventory__c
            FROM Season_Ticket_Line__c
            WHERE Season_Ticket__c = :seasonTicket.Id
        ];
        System.assertEquals('1', subject.Subject_Code__c);
        System.assertEquals('CLASSICO', subject.Name_IT__c);
        System.assertEquals(subject.Id, lineBeforeTarget.Subject__c);
        System.assertEquals(null, lineBeforeTarget.Target_Inventory__c);

        invokeInventoryApi(new List<Object>{ inventoryPayload(TARGET_PRODUCT_ID, false) });
        Inventory__c targetInventory = [
            SELECT Id FROM Inventory__c
            WHERE Inventory_Id__c = :String.valueOf(TARGET_PRODUCT_ID)
        ];
        System.assertEquals(targetInventory.Id, [
            SELECT Target_Inventory__c
            FROM Season_Ticket_Line__c
            WHERE Id = :lineBeforeTarget.Id
        ].Target_Inventory__c);

        invokeInventoryApi(new List<Object>{ inventoryPayload(OWNER_PRODUCT_ID, true) });
        System.assertEquals(1, [
            SELECT COUNT() FROM Season_Ticket_Subject__c
            WHERE Season_Ticket__c = :seasonTicket.Id
        ]);
        System.assertEquals(1, [
            SELECT COUNT() FROM Season_Ticket_Line__c
            WHERE Season_Ticket__c = :seasonTicket.Id
        ]);
    }

    @IsTest
    static void enrichmentApiMapsSeasonTicketRelationshipsWhenPayloadContainsThem() {
        Inventory__c owner = new Inventory__c(
            Name = 'Owner',
            Inventory_Id__c = String.valueOf(OWNER_PRODUCT_ID)
        );
        Inventory__c target = new Inventory__c(
            Name = 'Target',
            Inventory_Id__c = String.valueOf(TARGET_PRODUCT_ID)
        );
        insert new List<Inventory__c>{ owner, target };

        Map<String, Object> product = new Map<String, Object>{
            'productId' => OWNER_PRODUCT_ID,
            'found' => true,
            'code' => 'ST-01',
            'seasonTicket' => seasonTicketPayload()
        };
        CatalogEnrichmentService.Result result = CatalogEnrichmentService.applyResponse(
            new Map<String, Object>{ 'order' => new List<Object>{ product } }
        );

        System.assertEquals(1, result.seasonTicketsUpdated);
        System.assertEquals(1, result.seasonTicketSubjectsUpdated);
        System.assertEquals(1, result.seasonTicketLinesUpdated);
        Season_Ticket_Line__c line = [
            SELECT Season_Ticket__r.Inventory__c, Subject__c, Target_Inventory__c,
                   Placement_Type__c, Relationship_Key__c
            FROM Season_Ticket_Line__c
            LIMIT 1
        ];
        System.assertEquals(owner.Id, line.Season_Ticket__r.Inventory__c);
        System.assertNotEquals(null, line.Subject__c);
        System.assertEquals(target.Id, line.Target_Inventory__c);
        System.assertEquals('subject', line.Placement_Type__c);
        System.assert(line.Relationship_Key__c.contains(String.valueOf(LINE_ID)));
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

    private static Map<String, Object> inventoryPayload(Long productId, Boolean withSeasonTicket) {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => productId,
            'code' => productId == OWNER_PRODUCT_ID ? 'ST-01' : 'TARGET-01',
            'state' => 'RUNNING',
            'internalName' => new Map<String, Object>{
                'translations' => new List<Object>{
                    new Map<String, Object>{
                        'locale' => 'it',
                        'value' => productId == OWNER_PRODUCT_ID ? 'ABBONAMENTO' : 'SPETTACOLO'
                    }
                }
            }
        };
        if (withSeasonTicket) {
            payload.put('seasonTicket', seasonTicketPayload());
        }
        return payload;
    }

    private static Map<String, Object> seasonTicketPayload() {
        Map<String, Object> line = new Map<String, Object>{
            'seasonTicketLineId' => LINE_ID,
            'mandatoryEvent' => false,
            'multiplePerformances' => 'MULTI',
            'allowSeatCatUpDownGrade' => false,
            'product' => new Map<String, Object>{
                'id' => TARGET_PRODUCT_ID,
                'code' => 'TARGET-01'
            }
        };
        return new Map<String, Object>{
            'ticketPrintingMode' => 'CARD_AND_TICKETS',
            'seasonTicketLines' => new List<Object>(),
            'seasonTicketSubjects' => new List<Object>{
                new Map<String, Object>{
                    'code' => '1',
                    'rank' => 1,
                    'minEvents' => 0,
                    'maxEvents' => 5,
                    'externalName' => new Map<String, Object>{
                        'translations' => new List<Object>{
                            new Map<String, Object>{ 'locale' => 'it', 'value' => 'CLASSICO' },
                            new Map<String, Object>{ 'locale' => 'en', 'value' => 'CLASSIC' }
                        }
                    },
                    'seasonTicketLines' => new List<Object>{ line }
                }
            }
        };
    }
}
