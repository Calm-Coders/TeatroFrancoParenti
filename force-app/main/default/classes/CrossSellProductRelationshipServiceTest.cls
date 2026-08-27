@IsTest
private class CrossSellProductRelationshipServiceTest {
    private static final Long SOURCE_PRODUCT_ID = 10228691000001L;
    private static final Long TARGET_PRODUCT_ID = 10228691000002L;
    private static final Long SECOND_TARGET_PRODUCT_ID = 10228691000004L;
    private static final Long LINK_ID = 10228691000003L;

    @IsTest
    static void inventoryApiCreatesAndBackfillsTargetLookup() {
        invokeInventoryApi(new List<Object>{ inventoryPayload(SOURCE_PRODUCT_ID, true) });

        Cross_Sell_Product_Link__c linkBeforeTarget = [
            SELECT Id, Source_Inventory__r.Inventory_Id__c, Cross_Sell_Link_Id__c,
                   Target_Product_Id__c, Target_Inventory__c, Link_Type__c,
                   Message_IT__c, Start__c, End__c
            FROM Cross_Sell_Product_Link__c
        ];
        System.assertEquals(String.valueOf(SOURCE_PRODUCT_ID), linkBeforeTarget.Source_Inventory__r.Inventory_Id__c);
        System.assertEquals(String.valueOf(LINK_ID), linkBeforeTarget.Cross_Sell_Link_Id__c);
        System.assertEquals(String.valueOf(TARGET_PRODUCT_ID), linkBeforeTarget.Target_Product_Id__c);
        System.assertEquals(null, linkBeforeTarget.Target_Inventory__c);
        System.assertEquals('UP_SELL', linkBeforeTarget.Link_Type__c);
        System.assertEquals('Scegli anche il prodotto target', linkBeforeTarget.Message_IT__c);

        invokeInventoryApi(new List<Object>{ inventoryPayload(TARGET_PRODUCT_ID, false) });
        Inventory__c target = [
            SELECT Id FROM Inventory__c
            WHERE Inventory_Id__c = :String.valueOf(TARGET_PRODUCT_ID)
        ];
        System.assertEquals(target.Id, [
            SELECT Target_Inventory__c
            FROM Cross_Sell_Product_Link__c
            WHERE Id = :linkBeforeTarget.Id
        ].Target_Inventory__c);

        invokeInventoryApi(new List<Object>{ inventoryPayload(SOURCE_PRODUCT_ID, true) });
        System.assertEquals(1, [SELECT COUNT() FROM Cross_Sell_Product_Link__c]);
    }

    @IsTest
    static void enrichmentMapsNestedTargetAndDeletesExplicitlyRemovedLinks() {
        Inventory__c source = new Inventory__c(
            Name = 'Source', Inventory_Id__c = String.valueOf(SOURCE_PRODUCT_ID)
        );
        Inventory__c target = new Inventory__c(
            Name = 'Target', Inventory_Id__c = String.valueOf(TARGET_PRODUCT_ID)
        );
        insert new List<Inventory__c>{ source, target };

        Map<String, Object> product = enrichmentProduct(new List<Object>{
            new Map<String, Object>{
                'id' => LINK_ID,
                'type' => 'UP_SELL',
                'message' => 'Add the target product',
                'targetProduct' => new Map<String, Object>{
                    'id' => TARGET_PRODUCT_ID,
                    'name' => 'Target Product'
                }
            }
        });
        CatalogEnrichmentService.Result result = CatalogEnrichmentService.applyResponse(
            new Map<String, Object>{ 'order' => new List<Object>{ product } }
        );

        System.assertEquals(1, result.crossSellLinksUpdated);
        System.assertEquals(1, result.crossSellTargetsLinked);
        Cross_Sell_Product_Link__c link = [
            SELECT Source_Inventory__c, Target_Inventory__c, Target_Product_Name__c,
                   Message_IT__c, Relationship_Key__c, Raw_JSON__c
            FROM Cross_Sell_Product_Link__c
        ];
        System.assertEquals(source.Id, link.Source_Inventory__c);
        System.assertEquals(target.Id, link.Target_Inventory__c);
        System.assertEquals('Target Product', link.Target_Product_Name__c);
        System.assertEquals('Add the target product', link.Message_IT__c);
        System.assert(link.Relationship_Key__c.contains(String.valueOf(LINK_ID)));
        System.assert(link.Raw_JSON__c.contains('targetProduct'));

        CatalogEnrichmentService.Result removeResult = CatalogEnrichmentService.applyResponse(
            new Map<String, Object>{
                'order' => new List<Object>{ enrichmentProduct(new List<Object>()) }
            }
        );
        System.assertEquals(1, removeResult.crossSellLinksDeleted);
        System.assertEquals(0, [SELECT COUNT() FROM Cross_Sell_Product_Link__c]);
    }

    @IsTest
    static void repeatedExternalLinkIdSupportsMultipleTargets() {
        Inventory__c source = new Inventory__c(
            Name = 'Source', Inventory_Id__c = String.valueOf(SOURCE_PRODUCT_ID)
        );
        Inventory__c firstTarget = new Inventory__c(
            Name = 'First Target', Inventory_Id__c = String.valueOf(TARGET_PRODUCT_ID)
        );
        Inventory__c secondTarget = new Inventory__c(
            Name = 'Second Target', Inventory_Id__c = String.valueOf(SECOND_TARGET_PRODUCT_ID)
        );
        insert new List<Inventory__c>{ source, firstTarget, secondTarget };

        List<Object> links = new List<Object>{
            new Map<String, Object>{
                'id' => LINK_ID,
                'targetProductId' => TARGET_PRODUCT_ID,
                'targetProductRank' => 1,
                'start' => '0001-12-30T00:00:00.000+01:00'
            },
            new Map<String, Object>{
                'id' => LINK_ID,
                'targetProductId' => SECOND_TARGET_PRODUCT_ID,
                'targetProductRank' => 2
            }
        };
        CatalogEnrichmentService.Result result = CatalogEnrichmentService.applyResponse(
            new Map<String, Object>{
                'order' => new List<Object>{ enrichmentProduct(links) }
            }
        );

        System.assertEquals(2, result.crossSellLinksUpdated);
        System.assertEquals(2, result.crossSellTargetsLinked);
        System.assertEquals(2, [SELECT COUNT() FROM Cross_Sell_Product_Link__c]);
        System.assertEquals(2, [
            SELECT COUNT()
            FROM Cross_Sell_Product_Link__c
            WHERE Cross_Sell_Link_Id__c = :String.valueOf(LINK_ID)
              AND Target_Inventory__c != null
        ]);
        System.assertEquals(0, [
            SELECT COUNT()
            FROM Cross_Sell_Product_Link__c
            WHERE Start__c != null
        ]);
    }

    private static Map<String, Object> enrichmentProduct(List<Object> links) {
        return new Map<String, Object>{
            'productId' => SOURCE_PRODUCT_ID,
            'found' => true,
            'code' => 'SOURCE',
            'name_it' => 'Source',
            'crossSellProductLinks' => links
        };
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
            RestContext.response.responseBody == null ? null : RestContext.response.responseBody.toString()
        );
    }

    private static Map<String, Object> inventoryPayload(Long productId, Boolean includeLink) {
        List<Object> links = new List<Object>();
        if (includeLink) links.add(new Map<String, Object>{
            'id' => LINK_ID,
            'targetProductId' => TARGET_PRODUCT_ID,
            'type' => 'UP_SELL',
            'start' => '2026-08-01T00:00:00.000+02:00',
            'end' => '2026-12-31T23:59:59.000+01:00',
            'baseMinQuantity' => 1,
            'targetProductRank' => 1,
            'targetQuantityType' => 'FIXED',
            'targetSameDateAsBase' => false,
            'description' => new Map<String, Object>{
                'translations' => new List<Object>{
                    new Map<String, Object>{ 'locale' => 'it', 'value' => 'Scegli anche il prodotto target' },
                    new Map<String, Object>{ 'locale' => 'en', 'value' => 'Choose the target product too' }
                }
            }
        });
        return new Map<String, Object>{
            'id' => productId,
            'code' => productId == SOURCE_PRODUCT_ID ? 'SOURCE' : 'TARGET',
            'state' => 'RUNNING',
            'productFamilyType' => 'SEASONTICKET',
            'productFamilySubType' => 'SEASONTICKET',
            'internalName' => new Map<String, Object>{
                'translations' => new List<Object>{
                    new Map<String, Object>{
                        'locale' => 'it',
                        'value' => productId == SOURCE_PRODUCT_ID ? 'Source' : 'Target'
                    }
                }
            },
            'crossSellProductLinks' => links
        };
    }
}
