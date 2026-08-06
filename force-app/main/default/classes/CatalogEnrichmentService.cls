public without sharing class CatalogEnrichmentService {
    private static final Integer LONG_TEXT_LIMIT = 32768;

    public class Result {
        public Integer received = 0;
        public Integer found = 0;
        public Integer notFound = 0;
        public Integer missingInventory = 0;
        public Integer inventoriesUpdated = 0;
        public Integer eventsUpdated = 0;
        public Integer performancesUpdated = 0;
        public Integer seasonTicketsUpdated = 0;
        public Integer seasonTicketSubjectsUpdated = 0;
        public Integer seasonTicketLinesUpdated = 0;
        public Integer salesChannelsUpdated = 0;
        public Integer salePeriodsUpdated = 0;
        public Integer salePeriodAudiencesUpdated = 0;
        public Integer salePeriodSeatCategoriesUpdated = 0;
        public Integer seatCategoriesUpdated = 0;
        public Integer performanceSeatCategoriesUpdated = 0;
        public Integer audienceSubCategoriesUpdated = 0;
        public Integer salePeriodAudiencesLinked = 0;
        public Integer performancePricesUpdated = 0;
        public Integer performancePriceChargesUpdated = 0;
        public Integer venueLocationsUpdated = 0;
        public Integer performanceLocationsLinked = 0;
        public Integer crossSellLinksUpdated = 0;
        public Integer crossSellTargetsLinked = 0;
        public Integer crossSellLinksDeleted = 0;
        public List<String> errors = new List<String>();

        public Map<String, Object> toMap() {
            return new Map<String, Object>{
                'received' => received,
                'found' => found,
                'notFound' => notFound,
                'missingInventory' => missingInventory,
                'inventoriesUpdated' => inventoriesUpdated,
                'eventsUpdated' => eventsUpdated,
                'performancesUpdated' => performancesUpdated,
                'seasonTicketsUpdated' => seasonTicketsUpdated,
                'seasonTicketSubjectsUpdated' => seasonTicketSubjectsUpdated,
                'seasonTicketLinesUpdated' => seasonTicketLinesUpdated,
                'salesChannelsUpdated' => salesChannelsUpdated,
                'salePeriodsUpdated' => salePeriodsUpdated,
                'salePeriodAudiencesUpdated' => salePeriodAudiencesUpdated,
                'salePeriodSeatCategoriesUpdated' => salePeriodSeatCategoriesUpdated,
                'seatCategoriesUpdated' => seatCategoriesUpdated,
                'performanceSeatCategoriesUpdated' => performanceSeatCategoriesUpdated,
                'audienceSubCategoriesUpdated' => audienceSubCategoriesUpdated,
                'salePeriodAudiencesLinked' => salePeriodAudiencesLinked,
                'performancePricesUpdated' => performancePricesUpdated,
                'performancePriceChargesUpdated' => performancePriceChargesUpdated,
                'venueLocationsUpdated' => venueLocationsUpdated,
                'performanceLocationsLinked' => performanceLocationsLinked,
                'crossSellLinksUpdated' => crossSellLinksUpdated,
                'crossSellTargetsLinked' => crossSellTargetsLinked,
                'crossSellLinksDeleted' => crossSellLinksDeleted,
                'errors' => errors
            };
        }
    }

    public static Result applyResponse(Map<String, Object> responsePayload) {
        List<Object> products = responsePayload == null ? null : asList(responsePayload.get('order'));
        if (products == null && responsePayload != null) {
            products = asList(responsePayload.get('products'));
        }
        if (products == null && responsePayload != null) {
            Map<String, Object> nestedResponse = asMap(responsePayload.get('response'));
            products = nestedResponse == null ? null : asList(nestedResponse.get('order'));
            if (products == null && nestedResponse != null) {
                products = asList(nestedResponse.get('products'));
            }
        }
        if (products == null) {
            throw new CatalogEnrichmentException('The response must contain an order or products array.');
        }
        return applyProducts(products);
    }

    public static Result applyProducts(List<Object> rawProducts) {
        Result result = new Result();
        Map<Decimal, Map<String, Object>> productById = new Map<Decimal, Map<String, Object>>();
        for (Object rawProduct : rawProducts) {
            if (!(rawProduct instanceof Map<String, Object>)) {
                result.errors.add('Ignored a non-object order entry.');
                continue;
            }
            Map<String, Object> product = (Map<String, Object>) rawProduct;
            normalizeProductPayload(product);
            Decimal productId = asDecimal(product.get('productId'));
            if (productId == null) {
                result.errors.add('Ignored an order entry without productId.');
                continue;
            }
            productById.put(productId, product);
        }
        result.received = productById.size();
        if (productById.isEmpty()) {
            return result;
        }

        Map<Decimal, Inventory__c> inventoryByProductId = new Map<Decimal, Inventory__c>();
        for (Inventory__c inventory : [
            SELECT Id, Inventory_Id__c
            FROM Inventory__c
            WHERE Inventory_Id__c IN :productById.keySet()
        ]) {
            inventoryByProductId.put(inventory.Inventory_Id__c, inventory);
        }

        Datetime attemptTime = System.now();
        List<Inventory__c> inventoryUpdates = new List<Inventory__c>();
        Map<Id, Map<String, Object>> foundProductByInventoryId = new Map<Id, Map<String, Object>>();
        for (Decimal productId : productById.keySet()) {
            Map<String, Object> product = productById.get(productId);
            Inventory__c existing = inventoryByProductId.get(productId);
            if (existing == null) {
                result.missingInventory++;
                continue;
            }

            Inventory__c updateRecord = new Inventory__c(
                Id = existing.Id,
                Last_Enrichment_Attempt__c = attemptTime
            );
            Boolean wasFound = asBoolean(product.get('found')) == true;
            if (!wasFound) {
                result.notFound++;
                updateRecord.Enrichment_Status__c = 'Not Found';
                updateRecord.Enrichment_Error__c = truncate(asString(product.get('note')), LONG_TEXT_LIMIT);
                inventoryUpdates.add(updateRecord);
                continue;
            }

            result.found++;
            foundProductByInventoryId.put(existing.Id, product);
            updateRecord.Code__c = truncate(asString(product.get('code')), 255);
            updateRecord.Product_Family_Type__c = truncate(asString(product.get('productFamilyType')), 80);
            updateRecord.Product_Family_Sub_Type__c = truncate(asString(product.get('productFamilySubType')), 80);
            updateRecord.Audience_Type__c = truncate(asString(product.get('audienceType')), 80);
            updateRecord.State__c = truncate(asString(product.get('state')), 80);
            updateRecord.Waiting_List_Allowed__c = asBoolean(product.get('waitingListAllowed')) == true;
            updateRecord.Catalog_Name_IT__c = truncate(firstValue(product, new List<String>{ 'name_it', 'name' }), 255);
            updateRecord.Catalog_Name_EN__c = truncate(firstValue(product, new List<String>{ 'name_en', 'name' }), 255);
            updateRecord.Catalog_Description_IT__c = truncate(asString(product.get('description_it')), LONG_TEXT_LIMIT);
            updateRecord.Catalog_Description_EN__c = truncate(asString(product.get('description_en')), LONG_TEXT_LIMIT);

            Map<String, Object> season = asMap(product.get('season'));
            if (season != null) {
                updateRecord.Season_Id__c = truncate(asString(season.get('id')), 80);
                updateRecord.Season_Code__c = truncate(asString(season.get('code')), 80);
                updateRecord.Season_Name__c = truncate(firstValue(season, new List<String>{ 'name_it', 'name' }), 255);
                updateRecord.Season_Start__c = asDate(season.get('start'));
                updateRecord.Season_End__c = asDate(season.get('end'));
            }

            Map<String, Object> productType = asMap(product.get('productType'));
            if (productType != null) {
                updateRecord.Product_Type_Id__c = asDecimal(productType.get('id'));
                updateRecord.Product_Type_Code__c = truncate(asString(productType.get('code')), 80);
                updateRecord.Product_Type_Name__c = truncate(firstValue(productType, new List<String>{ 'name_it', 'name' }), 255);
            }
            Map<String, Object> ticketModel = asMap(product.get('ticketModel'));
            if (ticketModel != null) {
                updateRecord.Ticket_Model_Name__c = truncate(firstValue(ticketModel, new List<String>{ 'name_it', 'name' }), 255);
            }

            updateRecord.Ticket_Types__c = jsonValue(product.get('ticketTypes'));
            updateRecord.Product_Advantages__c = jsonValue(product.get('advantages'));
            updateRecord.Cross_Sell_Product_Links__c = jsonValue(product.get('crossSellProductLinks'));
            updateRecord.Sale_Periods__c = jsonValue(product.get('salePeriods'));
            if (product.containsKey('seasonTicket')) {
                updateRecord.Season_Ticket__c = jsonValue(product.get('seasonTicket'));
            }
            updateRecord.Enrichment_Status__c = 'Success';
            updateRecord.Enriched_On__c = attemptTime;
            updateRecord.Enrichment_Error__c = null;
            inventoryUpdates.add(updateRecord);
        }
        result.inventoriesUpdated = updateRecords(inventoryUpdates, result.errors, 'Inventory__c');

        applyActivities(foundProductByInventoryId, result);
        applyPerformances(foundProductByInventoryId, result);
        SalePeriodRelationshipService.Stats salePeriodStats =
            SalePeriodRelationshipService.syncEnrichment(foundProductByInventoryId);
        result.salesChannelsUpdated = salePeriodStats.salesChannelsUpserted;
        result.salePeriodsUpdated = salePeriodStats.salePeriodsUpserted;
        result.salePeriodAudiencesUpdated = salePeriodStats.audienceRestrictionsInserted;
        result.salePeriodSeatCategoriesUpdated = salePeriodStats.seatRestrictionsInserted;
        SeatCategoryRelationshipService.Stats seatCategoryStats =
            SeatCategoryRelationshipService.syncEnrichment(foundProductByInventoryId);
        result.seatCategoriesUpdated = seatCategoryStats.categoriesUpserted;
        result.performanceSeatCategoriesUpdated = seatCategoryStats.linksUpserted;
        PerformancePriceRelationshipService.Stats priceStats =
            PerformancePriceRelationshipService.syncEnrichment(foundProductByInventoryId);
        result.audienceSubCategoriesUpdated = priceStats.audiencesUpserted;
        result.salePeriodAudiencesLinked = priceStats.salePeriodAudiencesLinked;
        result.performancePricesUpdated = priceStats.pricesUpserted;
        result.performancePriceChargesUpdated = priceStats.priceChargesUpserted;
        VenueLocationRelationshipService.Stats locationStats =
            VenueLocationRelationshipService.syncEnrichment(foundProductByInventoryId);
        result.venueLocationsUpdated = locationStats.locationsUpserted;
        result.performanceLocationsLinked = locationStats.performancesLinked;
        CrossSellProductRelationshipService.Stats crossSellStats =
            CrossSellProductRelationshipService.syncEnrichment(foundProductByInventoryId);
        result.crossSellLinksUpdated = crossSellStats.linksUpserted;
        result.crossSellTargetsLinked = crossSellStats.targetsLinked;
        result.crossSellLinksDeleted = crossSellStats.linksDeleted;
        applySeasonTickets(foundProductByInventoryId, result);
        return result;
    }

    public static void markError(List<Long> productIds, String message) {
        if (productIds == null || productIds.isEmpty()) {
            return;
        }
        Set<Decimal> ids = new Set<Decimal>();
        for (Long productId : productIds) {
            if (productId != null) {
                ids.add(Decimal.valueOf(String.valueOf(productId)));
            }
        }
        List<Inventory__c> updates = new List<Inventory__c>();
        for (Inventory__c inventory : [
            SELECT Id
            FROM Inventory__c
            WHERE Inventory_Id__c IN :ids
        ]) {
            updates.add(new Inventory__c(
                Id = inventory.Id,
                Enrichment_Status__c = 'Error',
                Last_Enrichment_Attempt__c = System.now(),
                Enrichment_Error__c = truncate(message, LONG_TEXT_LIMIT)
            ));
        }
        if (!updates.isEmpty()) {
            Database.update(updates, false);
        }
    }

    private static void applyActivities(Map<Id, Map<String, Object>> productsByInventoryId, Result result) {
        if (productsByInventoryId.isEmpty()) {
            return;
        }
        Map<Id, Inventory_Event__c> eventByInventoryId = new Map<Id, Inventory_Event__c>();
        for (Inventory_Event__c eventRecord : [
            SELECT Id, Inventory__c
            FROM Inventory_Event__c
            WHERE Inventory__c IN :productsByInventoryId.keySet()
        ]) {
            eventByInventoryId.put(eventRecord.Inventory__c, eventRecord);
        }
        List<Inventory_Event__c> updates = new List<Inventory_Event__c>();
        for (Id inventoryId : productsByInventoryId.keySet()) {
            Map<String, Object> activity = asMap(productsByInventoryId.get(inventoryId).get('activity'));
            Inventory_Event__c existing = eventByInventoryId.get(inventoryId);
            if (activity == null || existing == null) {
                continue;
            }
            updates.add(new Inventory_Event__c(
                Id = existing.Id,
                Activity_Id__c = asDecimal(activity.get('id')),
                Activity_Code__c = truncate(asString(activity.get('code')), 255),
                Activity_Type__c = truncate(asString(activity.get('type')), 255),
                Activity_Name_IT__c = truncate(firstValue(activity, new List<String>{ 'name_it', 'name' }), 255),
                Activity_Name_EN__c = truncate(firstValue(activity, new List<String>{ 'name_en', 'name' }), 255)
            ));
        }
        result.eventsUpdated = updateRecords(updates, result.errors, 'Inventory_Event__c');
    }

    private static void applyPerformances(Map<Id, Map<String, Object>> productsByInventoryId, Result result) {
        Set<Decimal> performanceIds = new Set<Decimal>();
        Map<String, Map<String, Object>> payloadByCompositeKey = new Map<String, Map<String, Object>>();
        Map<Id, Decimal> productIdByInventoryId = new Map<Id, Decimal>();
        for (Inventory__c inventory : [
            SELECT Id, Inventory_Id__c
            FROM Inventory__c
            WHERE Id IN :productsByInventoryId.keySet()
        ]) {
            productIdByInventoryId.put(inventory.Id, inventory.Inventory_Id__c);
        }

        for (Id inventoryId : productsByInventoryId.keySet()) {
            Decimal productId = productIdByInventoryId.get(inventoryId);
            List<Object> performances = asList(productsByInventoryId.get(inventoryId).get('performances'));
            if (productId == null || performances == null) {
                continue;
            }
            for (Object rawPerformance : performances) {
                Map<String, Object> performance = asMap(rawPerformance);
                Decimal performanceId = performanceExternalId(performance);
                if (performanceId == null) {
                    continue;
                }
                performanceIds.add(performanceId);
                payloadByCompositeKey.put(numberKey(productId) + '|' + numberKey(performanceId), performance);
            }
        }
        if (performanceIds.isEmpty()) {
            return;
        }

        List<Performance__c> updates = new List<Performance__c>();
        for (Performance__c existing : [
            SELECT Id, Performance_Id__c, Inventory_Event__r.Inventory__c,
                   Inventory_Event__r.Inventory__r.Inventory_Id__c
            FROM Performance__c
            WHERE Performance_Id__c IN :performanceIds
              AND Inventory_Event__r.Inventory__c IN :productsByInventoryId.keySet()
        ]) {
            Decimal productId = existing.Inventory_Event__r.Inventory__r.Inventory_Id__c;
            Map<String, Object> performance = payloadByCompositeKey.get(
                numberKey(productId) + '|' + numberKey(existing.Performance_Id__c)
            );
            if (performance == null) {
                continue;
            }
            Map<String, Object> site = asMap(performance.get('site'));
            Map<String, Object> space = asMap(performance.get('space'));
            Map<String, Object> physical = asMap(performance.get('physicalConfiguration'));
            Map<String, Object> logical = asMap(performance.get('logicalConfiguration'));
            Map<String, Object> rateType = asMap(performance.get('rateType'));
            Map<String, Object> product = productsByInventoryId.get(existing.Inventory_Event__r.Inventory__c);
            String siteCode = preferredValue(site, performance, 'code', 'siteCode');
            String spaceCode = preferredValue(space, performance, 'code', 'spaceCode');
            Decimal siteId = preferredDecimal(site, performance, 'id', 'siteId');
            Decimal spaceId = preferredDecimal(space, performance, 'id', 'spaceId');
            updates.add(new Performance__c(
                Id = existing.Id,
                Code__c = truncate(asString(performance.get('code')), 255),
                Start__c = asDatetime(performance.get('start')),
                Duration__c = asDecimal(performance.get('duration')),
                Space_Id__c = spaceId,
                Space_Code__c = truncate(spaceCode, 255),
                Site_Id__c = siteId,
                Site_Code__c = truncate(siteCode, 255),
                State__c = truncate(asString(performance.get('state')), 255),
                Site_Name_IT__c = truncate(preferredName(performance, site, 'siteName_it', 'name_it'), 255),
                Site_Name_EN__c = truncate(preferredName(performance, site, 'siteName_en', 'name_en'), 255),
                Space_Name_IT__c = truncate(preferredName(performance, space, 'spaceName_it', 'name_it'), 255),
                Space_Name_EN__c = truncate(preferredName(performance, space, 'spaceName_en', 'name_en'), 255),
                Location__c = jsonValue(locationAudit(site, space, performance)),
                Physical_Configuration_Id__c = asDecimal(physical == null ? null : physical.get('id')),
                Physical_Configuration_Name__c = truncate(firstValue(physical, new List<String>{ 'name_it', 'name' }), 255),
                Logical_Configuration_Id__c = asDecimal(logical == null ? null : logical.get('id')),
                Logical_Configuration_Name__c = truncate(firstValue(logical, new List<String>{ 'name_it', 'name' }), 255),
                Rate_Type_Id__c = asDecimal(rateType == null ? null : rateType.get('id')),
                Rate_Type_Code__c = truncate(firstValue(rateType, new List<String>{ 'code' }), 255),
                Rate_Type_Name__c = truncate(firstValue(rateType, new List<String>{ 'name_it', 'name' }), 255),
                Sale_Periods__c = jsonValue(performance.get('salePeriods')),
                Tariff_Legend__c = jsonValue(product == null ? null : product.get('ticketTypes'))
            ));
        }
        result.performancesUpdated = updateRecords(updates, result.errors, 'Performance__c');
    }

    private static void applySeasonTickets(
        Map<Id, Map<String, Object>> productsByInventoryId,
        Result result
    ) {
        Set<Id> scopedInventoryIds = new Set<Id>();
        for (Id inventoryId : productsByInventoryId.keySet()) {
            if (asMap(productsByInventoryId.get(inventoryId).get('seasonTicket')) != null) {
                scopedInventoryIds.add(inventoryId);
            }
        }
        if (scopedInventoryIds.isEmpty()) {
            return;
        }

        Map<Id, Season_Ticket__c> existingByInventoryId = new Map<Id, Season_Ticket__c>();
        for (Season_Ticket__c existing : [
            SELECT Id, Inventory__c
            FROM Season_Ticket__c
            WHERE Inventory__c IN :scopedInventoryIds
        ]) {
            existingByInventoryId.put(existing.Inventory__c, existing);
        }

        List<Season_Ticket__c> seasonTickets = new List<Season_Ticket__c>();
        Map<Id, Map<String, Object>> payloadByInventoryId = new Map<Id, Map<String, Object>>();
        for (Id inventoryId : scopedInventoryIds) {
            Map<String, Object> product = productsByInventoryId.get(inventoryId);
            Map<String, Object> seasonTicketPayload = asMap(product.get('seasonTicket'));
            Season_Ticket__c seasonTicket = new Season_Ticket__c(
                Name = truncate(
                    'Season Ticket ' + numberKey(asDecimal(product.get('productId'))),
                    80
                ),
                Inventory__c = inventoryId,
                Championship_Season_Ticket__c = asBoolean(
                    seasonTicketPayload.get('championshipSeasonTicket')
                ) == true,
                Fixed_Seat__c = asBoolean(seasonTicketPayload.get('fixedSeat')) == true,
                Ticket_Printing_Mode__c = truncate(
                    asString(seasonTicketPayload.get('ticketPrintingMode')),
                    255
                ),
                Season_Ticket_Subjects__c = jsonValue(
                    seasonTicketPayload.get('seasonTicketSubjects')
                ),
                Season_Ticket_Lines__c = jsonValue(
                    seasonTicketPayload.get('seasonTicketLines')
                )
            );
            if (existingByInventoryId.containsKey(inventoryId)) {
                seasonTicket.Id = existingByInventoryId.get(inventoryId).Id;
            }
            seasonTickets.add(seasonTicket);
            payloadByInventoryId.put(inventoryId, seasonTicketPayload);
        }
        upsert seasonTickets;
        result.seasonTicketsUpdated = seasonTickets.size();

        Map<Id, Map<String, Object>> payloadBySeasonTicketId = new Map<Id, Map<String, Object>>();
        Map<Id, Decimal> ownerProductIdBySeasonTicketId = new Map<Id, Decimal>();
        for (Season_Ticket__c seasonTicket : seasonTickets) {
            Map<String, Object> product = productsByInventoryId.get(seasonTicket.Inventory__c);
            payloadBySeasonTicketId.put(
                seasonTicket.Id,
                payloadByInventoryId.get(seasonTicket.Inventory__c)
            );
            ownerProductIdBySeasonTicketId.put(
                seasonTicket.Id,
                asDecimal(product.get('productId'))
            );
        }
        SeasonTicketRelationshipService.Stats relationshipStats =
            SeasonTicketRelationshipService.sync(
                payloadBySeasonTicketId,
                ownerProductIdBySeasonTicketId
            );
        result.seasonTicketSubjectsUpdated = relationshipStats.subjectsUpserted;
        result.seasonTicketLinesUpdated = relationshipStats.linesUpserted;
    }

    private static Integer updateRecords(List<SObject> records, List<String> errors, String label) {
        if (records.isEmpty()) {
            return 0;
        }
        Integer successes = 0;
        Database.SaveResult[] saveResults = Database.update(records, false);
        for (Integer index = 0; index < saveResults.size(); index++) {
            if (saveResults[index].isSuccess()) {
                successes++;
                continue;
            }
            for (Database.Error error : saveResults[index].getErrors()) {
                errors.add(label + ' ' + records[index].Id + ': ' + error.getMessage());
            }
        }
        return successes;
    }

    private static String preferredName(Map<String, Object> flat, Map<String, Object> nested, String flatKey, String nestedKey) {
        String value = firstValue(nested, new List<String>{ nestedKey, 'name' });
        if (!String.isBlank(value)) {
            return value;
        }
        return flat == null ? null : asString(flat.get(flatKey));
    }

    private static String preferredValue(
        Map<String, Object> nested,
        Map<String, Object> flat,
        String nestedKey,
        String flatKey
    ) {
        String value = nested == null ? null : asString(nested.get(nestedKey));
        return String.isBlank(value) && flat != null ? asString(flat.get(flatKey)) : value;
    }

    private static Decimal preferredDecimal(
        Map<String, Object> nested,
        Map<String, Object> flat,
        String nestedKey,
        String flatKey
    ) {
        Decimal value = nested == null ? null : asDecimal(nested.get(nestedKey));
        return value == null && flat != null ? asDecimal(flat.get(flatKey)) : value;
    }

    private static Map<String, Object> locationAudit(
        Map<String, Object> site,
        Map<String, Object> space,
        Map<String, Object> performance
    ) {
        Map<String, Object> audit = new Map<String, Object>{
            'site' => site,
            'space' => space,
            'siteCode' => preferredValue(site, performance, 'code', 'siteCode'),
            'spaceCode' => preferredValue(space, performance, 'code', 'spaceCode')
        };
        return audit;
    }

    private static Decimal performanceExternalId(Map<String, Object> performance) {
        if (performance == null) {
            return null;
        }
        Decimal value = asDecimal(performance.get('id'));
        return value == null ? asDecimal(performance.get('performanceId')) : value;
    }

    private static void normalizeProductPayload(Map<String, Object> product) {
        if (product == null) {
            return;
        }
        Map<String, Object> eventPayload = asMap(product.get('event'));
        if (eventPayload != null) {
            if (product.get('activity') == null && eventPayload.get('activity') != null) {
                product.put('activity', eventPayload.get('activity'));
            }
            if (product.get('performances') == null && eventPayload.get('performances') != null) {
                product.put('performances', eventPayload.get('performances'));
            }
        }
        List<Object> performances = asList(product.get('performances'));
        if (performances == null) {
            return;
        }
        for (Object rawPerformance : performances) {
            Map<String, Object> performance = asMap(rawPerformance);
            if (performance != null && performance.get('id') == null && performance.get('performanceId') != null) {
                performance.put('id', performance.get('performanceId'));
            }
        }
    }

    private static String firstValue(Map<String, Object> source, List<String> keys) {
        if (source == null) {
            return null;
        }
        for (String key : keys) {
            String value = asString(source.get(key));
            if (!String.isBlank(value)) {
                return value;
            }
        }
        return null;
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : null;
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Decimal asDecimal(Object value) {
        try {
            return value == null ? null : Decimal.valueOf(String.valueOf(value));
        } catch (Exception ignored) {
            return null;
        }
    }

    private static Boolean asBoolean(Object value) {
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return value == null ? null : String.valueOf(value).toLowerCase() == 'true';
    }

    private static Date asDate(Object value) {
        String text = asString(value);
        if (String.isBlank(text) || text.length() < 10) {
            return null;
        }
        try {
            return Date.valueOf(text.substring(0, 10));
        } catch (Exception ignored) {
            return null;
        }
    }

    private static Datetime asDatetime(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize(JSON.serialize(value), Datetime.class);
        } catch (Exception ignored) {
            String text = asString(value);
            try {
                return Datetime.valueOf(text.substring(0, 19).replace('T', ' '));
            } catch (Exception alsoIgnored) {
                return null;
            }
        }
    }

    private static String jsonValue(Object value) {
        return value == null ? null : truncate(JSON.serialize(value), LONG_TEXT_LIMIT);
    }

    private static String truncate(String value, Integer length) {
        return value == null || value.length() <= length ? value : value.substring(0, length);
    }

    private static String numberKey(Decimal value) {
        return value == null ? '' : String.valueOf(value.setScale(0));
    }

    public class CatalogEnrichmentException extends Exception {
    }
}
