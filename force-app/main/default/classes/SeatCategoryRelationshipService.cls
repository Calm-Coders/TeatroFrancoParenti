public with sharing class SeatCategoryRelationshipService {
    private static final Integer LONG_TEXT_LIMIT = 32768;

    public class Stats {
        public Integer categoriesUpserted = 0;
        public Integer linksUpserted = 0;
        public Integer linksDeleted = 0;
    }

    public static Stats syncInventoryPayloads(
        List<InventoryWrapper> products,
        List<Inventory__c> inventories,
        List<Performance__c> performances
    ) {
        Map<Id, Id> inventoryIdByEventId = new Map<Id, Id>();
        Set<Id> eventIds = new Set<Id>();
        for (Performance__c performance : performances) {
            if (performance.Inventory_Event__c != null) eventIds.add(performance.Inventory_Event__c);
        }
        for (Inventory_Event__c eventRecord : [
            SELECT Id, Inventory__c FROM Inventory_Event__c WHERE Id IN :eventIds
        ]) {
            inventoryIdByEventId.put(eventRecord.Id, eventRecord.Inventory__c);
        }

        Map<String, Performance__c> performanceByOwnerAndExternalId = new Map<String, Performance__c>();
        for (Performance__c performance : performances) {
            Id inventoryId = inventoryIdByEventId.get(performance.Inventory_Event__c);
            if (inventoryId != null && performance.Performance_Id__c != null) {
                performanceByOwnerAndExternalId.put(
                    String.valueOf(inventoryId) + '|' + numberKey(performance.Performance_Id__c),
                    performance
                );
            }
        }

        Map<Id, List<Object>> categoriesByPerformanceId = new Map<Id, List<Object>>();
        for (Integer productIndex = 0; productIndex < products.size(); productIndex++) {
            InventoryWrapper product = products[productIndex];
            Inventory__c inventory = inventories[productIndex];
            Map<String, Object> eventPayload = asMap(product.event);
            List<Object> rawPerformances = eventPayload == null ? null : asList(eventPayload.get('performances'));
            if (rawPerformances == null) continue;
            for (Object rawPerformance : rawPerformances) {
                Map<String, Object> performancePayload = asMap(rawPerformance);
                Decimal externalId = performancePayload == null ? null : asDecimal(performancePayload.get('id'));
                Performance__c performance = externalId == null ? null : performanceByOwnerAndExternalId.get(
                    String.valueOf(inventory.Id) + '|' + numberKey(externalId)
                );
                List<Object> categories = extractCategories(performancePayload);
                if (performance != null && categories != null) {
                    categoriesByPerformanceId.put(performance.Id, categories);
                }
            }
        }
        return sync(categoriesByPerformanceId);
    }

    public static Stats syncEnrichment(Map<Id, Map<String, Object>> productsByInventoryId) {
        Set<Id> inventoryIds = productsByInventoryId.keySet();
        Map<String, Performance__c> performanceByOwnerAndExternalId = new Map<String, Performance__c>();
        for (Performance__c performance : [
            SELECT Id, Performance_Id__c, Inventory_Event__r.Inventory__c
            FROM Performance__c WHERE Inventory_Event__r.Inventory__c IN :inventoryIds
        ]) {
            performanceByOwnerAndExternalId.put(
                String.valueOf(performance.Inventory_Event__r.Inventory__c) + '|' + numberKey(performance.Performance_Id__c),
                performance
            );
        }

        Map<Id, List<Object>> categoriesByPerformanceId = new Map<Id, List<Object>>();
        for (Id inventoryId : inventoryIds) {
            List<Object> rawPerformances = asList(productsByInventoryId.get(inventoryId).get('performances'));
            if (rawPerformances == null) continue;
            for (Object rawPerformance : rawPerformances) {
                Map<String, Object> performancePayload = asMap(rawPerformance);
                Decimal externalId = performancePayload == null ? null : asDecimal(performancePayload.get('id'));
                Performance__c performance = externalId == null ? null : performanceByOwnerAndExternalId.get(
                    String.valueOf(inventoryId) + '|' + numberKey(externalId)
                );
                List<Object> categories = extractCategories(performancePayload);
                if (performance != null && categories != null) {
                    categoriesByPerformanceId.put(performance.Id, categories);
                }
            }
        }
        return sync(categoriesByPerformanceId);
    }

    public static Stats syncStoredPerformances(List<Performance__c> performances) {
        Map<Id, List<Object>> categoriesByPerformanceId = new Map<Id, List<Object>>();
        for (Performance__c performance : performances) {
            if (performance.Id == null || String.isBlank(performance.Seat_Categories__c)) continue;
            try {
                List<Object> categories = asList(JSON.deserializeUntyped(performance.Seat_Categories__c));
                if (categories != null) categoriesByPerformanceId.put(performance.Id, categories);
            } catch (Exception ignored) {
                // Preserve the raw JSON and skip malformed historical rows.
            }
        }
        return sync(categoriesByPerformanceId);
    }

    private static Stats sync(Map<Id, List<Object>> categoriesByPerformanceId) {
        Stats stats = new Stats();
        if (categoriesByPerformanceId.isEmpty()) return stats;
        Set<Id> performanceIds = categoriesByPerformanceId.keySet();

        Map<String, Seat_Category__c> categoryByKey = new Map<String, Seat_Category__c>();
        Map<Id, List<String>> categoryKeysByPerformanceId = new Map<Id, List<String>>();
        Map<String, Map<String, Object>> payloadByCompositeKey = new Map<String, Map<String, Object>>();
        for (Id performanceId : categoriesByPerformanceId.keySet()) {
            List<String> keys = new List<String>();
            Set<String> seen = new Set<String>();
            for (Object rawCategory : categoriesByPerformanceId.get(performanceId)) {
                Map<String, Object> payload = asMap(rawCategory);
                String categoryKey = categoryKey(payload);
                if (payload == null || String.isBlank(categoryKey) || seen.contains(categoryKey)) continue;
                seen.add(categoryKey);
                keys.add(categoryKey);
                categoryByKey.put(categoryKey, buildCategory(categoryKey, payload));
                payloadByCompositeKey.put(String.valueOf(performanceId) + '|' + categoryKey, payload);
            }
            categoryKeysByPerformanceId.put(performanceId, keys);
        }

        List<Seat_Category__c> categories = categoryByKey.values();
        if (!categories.isEmpty()) {
            upsert categories Category_Key__c;
            stats.categoriesUpserted = categories.size();
        }
        categoryByKey.clear();
        for (Seat_Category__c category : categories) categoryByKey.put(category.Category_Key__c, category);

        List<Performance_Seat_Category__c> links = new List<Performance_Seat_Category__c>();
        Set<String> desiredKeys = new Set<String>();
        for (Id performanceId : categoryKeysByPerformanceId.keySet()) {
            List<String> categoryKeys = categoryKeysByPerformanceId.get(performanceId);
            for (Integer sequence = 0; sequence < categoryKeys.size(); sequence++) {
                String categoryKey = categoryKeys[sequence];
                String relationshipKey = String.valueOf(performanceId) + '|' + categoryKey;
                desiredKeys.add(relationshipKey);
                links.add(new Performance_Seat_Category__c(
                    Relationship_Key__c = relationshipKey,
                    Performance__c = performanceId,
                    Seat_Category__c = categoryByKey.get(categoryKey).Id,
                    Sequence__c = sequence,
                    Raw_JSON__c = truncate(JSON.serialize(payloadByCompositeKey.get(relationshipKey)), LONG_TEXT_LIMIT)
                ));
            }
        }
        if (!links.isEmpty()) {
            upsert links Relationship_Key__c;
            stats.linksUpserted = links.size();
        }

        List<Performance_Seat_Category__c> stale = new List<Performance_Seat_Category__c>();
        for (Performance_Seat_Category__c existing : [
            SELECT Id, Relationship_Key__c FROM Performance_Seat_Category__c
            WHERE Performance__c IN :performanceIds
        ]) {
            if (!desiredKeys.contains(existing.Relationship_Key__c)) stale.add(existing);
        }
        if (!stale.isEmpty()) {
            delete stale;
            stats.linksDeleted = stale.size();
        }
        return stats;
    }

    private static List<Object> extractCategories(Map<String, Object> performancePayload) {
        if (performancePayload == null) return null;
        if (performancePayload.containsKey('seatCategories')) return asList(performancePayload.get('seatCategories'));
        List<Object> priceGrid = asList(performancePayload.get('priceGrid'));
        if (priceGrid == null) return null;
        List<Object> categories = new List<Object>();
        for (Object rawPrice : priceGrid) {
            Map<String, Object> price = asMap(rawPrice);
            if (price != null && price.get('seatCategory') != null) categories.add(price.get('seatCategory'));
        }
        return categories;
    }

    private static Seat_Category__c buildCategory(String key, Map<String, Object> payload) {
        String nameIt = translatedValue(payload.get('externalName'), 'it');
        String nameEn = translatedValue(payload.get('externalName'), 'en');
        if (String.isBlank(nameIt)) nameIt = asString(payload.get('name'));
        if (String.isBlank(nameEn)) nameEn = nameIt;
        String displayName = !String.isBlank(nameIt) ? nameIt : asString(payload.get('code'));
        if (String.isBlank(displayName)) displayName = 'Seat Category ' + key;
        return new Seat_Category__c(
            Name = truncate(displayName, 80),
            Category_Key__c = key,
            Seat_Category_Id__c = asDecimal(payload.get('id')),
            Code__c = truncate(asString(payload.get('code')), 80),
            Institution_Category_Id__c = asDecimal(payload.get('institutionCategoryId')),
            Category_Number__c = truncate(asString(payload.get('catNum')), 80),
            Name_IT__c = truncate(nameIt, 255),
            Name_EN__c = truncate(nameEn, 255),
            Rank__c = asDecimal(payload.get('rank')),
            Text_Color__c = truncate(asString(payload.get('textColor')), 20),
            Background_Color__c = truncate(asString(payload.get('bgColor')), 20),
            Same_Block_Restriction_Mode__c = truncate(asString(payload.get('sameBlockRestrictionMode')), 80),
            Pre_Request_Logical_Seat_Category_Ids__c = truncate(JSON.serialize(payload.get('preRequestLogicalSeatCatIds')), LONG_TEXT_LIMIT),
            Raw_JSON__c = truncate(JSON.serialize(payload), LONG_TEXT_LIMIT)
        );
    }

    private static String categoryKey(Map<String, Object> payload) {
        if (payload == null) return null;
        Decimal externalId = asDecimal(payload.get('id'));
        if (externalId != null) return numberKey(externalId);
        String code = asString(payload.get('code'));
        return String.isBlank(code) ? null : 'CODE:' + code;
    }

    private static String translatedValue(Object rawValue, String locale) {
        Map<String, Object> value = asMap(rawValue);
        List<Object> translations = value == null ? null : asList(value.get('translations'));
        String fallback;
        if (translations != null) {
            for (Object rawTranslation : translations) {
                Map<String, Object> translation = asMap(rawTranslation);
                String translated = translation == null ? null : asString(translation.get('value'));
                if (String.isBlank(translated)) continue;
                if (asString(translation.get('locale')) == locale) return translated;
                if (fallback == null) fallback = translated;
            }
        }
        return fallback;
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }
    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : null;
    }
    private static Decimal asDecimal(Object value) {
        if (value == null) return null;
        try { return Decimal.valueOf(String.valueOf(value)); } catch (Exception ignored) { return null; }
    }
    private static String asString(Object value) { return value == null ? null : String.valueOf(value); }
    private static String numberKey(Decimal value) { return value == null ? null : value.setScale(0).toPlainString(); }
    private static String truncate(String value, Integer limitValue) {
        return value == null || value.length() <= limitValue ? value : value.substring(0, limitValue);
    }
}
