public without sharing class VenueLocationRelationshipService {
    private static final Integer LONG_TEXT_LIMIT = 32768;

    public class Stats {
        public Integer locationsUpserted = 0;
        public Integer performancesLinked = 0;
    }

    public static Stats syncInventoryPayloads(
        List<InventoryWrapper> products,
        List<Inventory__c> inventories,
        List<Performance__c> performances
    ) {
        Set<Id> eventIds = new Set<Id>();
        for (Performance__c performance : performances) if (performance.Inventory_Event__c != null) eventIds.add(performance.Inventory_Event__c);
        Map<Id, Id> inventoryIdByEventId = new Map<Id, Id>();
        if (!eventIds.isEmpty()) for (Inventory_Event__c eventRecord : [
            SELECT Id, Inventory__c FROM Inventory_Event__c WHERE Id IN :eventIds
        ]) inventoryIdByEventId.put(eventRecord.Id, eventRecord.Inventory__c);

        Map<String, Performance__c> performanceByOwnerAndExternalId = new Map<String, Performance__c>();
        for (Performance__c performance : performances) {
            Id inventoryId = inventoryIdByEventId.get(performance.Inventory_Event__c);
            if (inventoryId != null && performance.Performance_Id__c != null) {
                performanceByOwnerAndExternalId.put(
                    String.valueOf(inventoryId) + '|' + numberKey(performance.Performance_Id__c), performance
                );
            }
        }

        Map<Id, Map<String, Object>> locationByPerformanceId = new Map<Id, Map<String, Object>>();
        for (Integer productIndex = 0; productIndex < products.size(); productIndex++) {
            Map<String, Object> eventPayload = asMap(products[productIndex].event);
            List<Object> rawPerformances = eventPayload == null ? null : asList(eventPayload.get('performances'));
            if (rawPerformances == null) continue;
            for (Object rawPerformance : rawPerformances) {
                Map<String, Object> payload = asMap(rawPerformance);
                Decimal externalId = payload == null ? null : asDecimal(payload.get('id'));
                Performance__c performance = externalId == null ? null : performanceByOwnerAndExternalId.get(
                    String.valueOf(inventories[productIndex].Id) + '|' + numberKey(externalId)
                );
                Map<String, Object> location = extractLocation(payload);
                if (performance != null && location != null) locationByPerformanceId.put(performance.Id, location);
            }
        }
        return sync(locationByPerformanceId);
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
        Map<Id, Map<String, Object>> locationByPerformanceId = new Map<Id, Map<String, Object>>();
        for (Id inventoryId : inventoryIds) {
            List<Object> rawPerformances = asList(productsByInventoryId.get(inventoryId).get('performances'));
            if (rawPerformances == null) continue;
            for (Object rawPerformance : rawPerformances) {
                Map<String, Object> payload = asMap(rawPerformance);
                Decimal externalId = payload == null ? null : asDecimal(payload.get('id'));
                Performance__c performance = externalId == null ? null : performanceByOwnerAndExternalId.get(
                    String.valueOf(inventoryId) + '|' + numberKey(externalId)
                );
                Map<String, Object> location = extractLocation(payload);
                if (performance != null && location != null) locationByPerformanceId.put(performance.Id, location);
            }
        }
        return sync(locationByPerformanceId);
    }

    public static Stats syncStoredPerformances(List<Performance__c> performances) {
        Map<Id, Map<String, Object>> locationByPerformanceId = new Map<Id, Map<String, Object>>();
        for (Performance__c performance : performances) {
            if (performance.Id == null) continue;
            Map<String, Object> location;
            if (!String.isBlank(performance.Location__c)) {
                try { location = asMap(JSON.deserializeUntyped(performance.Location__c)); }
                catch (Exception ignored) { location = null; }
            }
            if (location != null) {
                Map<String, Object> normalizedLocation = extractLocation(location);
                if (normalizedLocation != null) location = normalizedLocation;
            }
            if (location == null) {
                location = new Map<String, Object>{
                    'siteCode' => performance.Site_Code__c,
                    'spaceCode' => performance.Space_Code__c,
                    'siteName_it' => performance.Site_Name_IT__c,
                    'siteName_en' => performance.Site_Name_EN__c,
                    'spaceName_it' => performance.Space_Name_IT__c,
                    'spaceName_en' => performance.Space_Name_EN__c
                };
            }
            if (!String.isBlank(locationKey(location))) locationByPerformanceId.put(performance.Id, location);
        }
        return sync(locationByPerformanceId);
    }

    private static Stats sync(Map<Id, Map<String, Object>> locationByPerformanceId) {
        Stats stats = new Stats();
        if (locationByPerformanceId.isEmpty()) return stats;
        Map<String, Map<String, Object>> payloadByKey = new Map<String, Map<String, Object>>();
        Map<Id, String> keyByPerformanceId = new Map<Id, String>();
        for (Id performanceId : locationByPerformanceId.keySet()) {
            Map<String, Object> payload = locationByPerformanceId.get(performanceId);
            String key = locationKey(payload);
            if (String.isBlank(key)) continue;
            keyByPerformanceId.put(performanceId, key);
            payloadByKey.put(key, mergeLocationPayload(payloadByKey.get(key), payload));
        }
        if (payloadByKey.isEmpty()) return stats;

        Set<String> keys = payloadByKey.keySet();
        Map<String, Venue_Location__c> locationByKey = new Map<String, Venue_Location__c>();
        for (Venue_Location__c existing : [
            SELECT Id, Location_Key__c FROM Venue_Location__c WHERE Location_Key__c IN :keys
        ]) locationByKey.put(existing.Location_Key__c, existing);

        List<Venue_Location__c> locations = new List<Venue_Location__c>();
        for (String key : keys) locations.add(buildLocation(key, payloadByKey.get(key)));
        upsert locations Location_Key__c;
        stats.locationsUpserted = locations.size();
        for (Venue_Location__c location : locations) locationByKey.put(location.Location_Key__c, location);

        List<Performance__c> updates = new List<Performance__c>();
        for (Id performanceId : keyByPerformanceId.keySet()) {
            Venue_Location__c location = locationByKey.get(keyByPerformanceId.get(performanceId));
            if (location != null) updates.add(new Performance__c(Id = performanceId, Venue_Location__c = location.Id));
        }
        if (!updates.isEmpty()) update updates;
        stats.performancesLinked = updates.size();
        return stats;
    }

    private static Venue_Location__c buildLocation(String key, Map<String, Object> payload) {
        String siteIt = preferredName(payload, 'siteName_it', 'siteExternalName', 'it');
        String siteEn = preferredName(payload, 'siteName_en', 'siteExternalName', 'en');
        String spaceIt = preferredName(payload, 'spaceName_it', 'spaceExternalName', 'it');
        String spaceEn = preferredName(payload, 'spaceName_en', 'spaceExternalName', 'en');
        String displayName = !String.isBlank(spaceIt) ? spaceIt : asString(payload.get('spaceCode'));
        if (String.isBlank(displayName)) displayName = siteIt;
        else if (!String.isBlank(siteIt) && siteIt != displayName) displayName += ' - ' + siteIt;
        if (String.isBlank(displayName)) displayName = key;
        return new Venue_Location__c(
            Name = truncate(displayName, 80), Location_Key__c = key,
            Site_Id__c = idKey(payload.get('siteId')),
            Site_Code__c = truncate(asString(payload.get('siteCode')), 80),
            Space_Id__c = idKey(payload.get('spaceId')),
            Space_Code__c = truncate(asString(payload.get('spaceCode')), 80),
            Site_Name_IT__c = truncate(siteIt, 255), Site_Name_EN__c = truncate(siteEn, 255),
            Space_Name_IT__c = truncate(spaceIt, 255), Space_Name_EN__c = truncate(spaceEn, 255),
            Town__c = truncate(asString(payload.get('town')), 255),
            Address__c = truncate(asString(payload.get('address')), 255),
            Raw_JSON__c = truncate(JSON.serialize(payload), LONG_TEXT_LIMIT)
        );
    }

    private static Map<String, Object> extractLocation(Map<String, Object> performance) {
        if (performance == null) return null;
        Map<String, Object> sourceLocation = asMap(performance.get('location'));
        Map<String, Object> site = asMap(performance.get('site'));
        Map<String, Object> space = asMap(performance.get('space'));

        String siteCode = firstString(
            site == null ? null : site.get('code'),
            sourceLocation == null ? null : sourceLocation.get('siteCode'),
            performance.get('siteCode')
        );
        String spaceCode = firstString(
            space == null ? null : space.get('code'),
            sourceLocation == null ? null : sourceLocation.get('spaceCode'),
            performance.get('spaceCode')
        );
        if (String.isBlank(siteCode) && String.isBlank(spaceCode)) return null;

        Map<String, Object> location = new Map<String, Object>{
            'siteCode' => siteCode, 'spaceCode' => spaceCode,
            'siteId' => firstObject(
                site == null ? null : site.get('id'),
                sourceLocation == null ? null : sourceLocation.get('siteId'),
                performance.get('siteId')
            ),
            'spaceId' => firstObject(
                space == null ? null : space.get('id'),
                sourceLocation == null ? null : sourceLocation.get('spaceId'),
                performance.get('spaceId')
            ),
            'siteName_it' => firstString(
                nestedName(site, 'name_it'),
                sourceLocation == null ? null : sourceLocation.get('siteName_it'),
                performance.get('siteName_it')
            ),
            'siteName_en' => firstString(
                nestedName(site, 'name_en'),
                sourceLocation == null ? null : sourceLocation.get('siteName_en'),
                performance.get('siteName_en')
            ),
            'spaceName_it' => firstString(
                nestedName(space, 'name_it'),
                sourceLocation == null ? null : sourceLocation.get('spaceName_it'),
                performance.get('spaceName_it')
            ),
            'spaceName_en' => firstString(
                nestedName(space, 'name_en'),
                sourceLocation == null ? null : sourceLocation.get('spaceName_en'),
                performance.get('spaceName_en')
            ),
            'siteExternalName' => firstObject(
                sourceLocation == null ? null : sourceLocation.get('siteExternalName'),
                performance.get('siteExternalName')
            ),
            'spaceExternalName' => firstObject(
                sourceLocation == null ? null : sourceLocation.get('spaceExternalName'),
                performance.get('spaceExternalName')
            ),
            'town' => firstObject(
                site == null ? null : site.get('town'),
                sourceLocation == null ? null : sourceLocation.get('town')
            ),
            'address' => firstObject(
                site == null ? null : site.get('address'),
                sourceLocation == null ? null : sourceLocation.get('address')
            ),
            'site' => site,
            'space' => space
        };
        if (sourceLocation != null) location.put('sourceLocation', sourceLocation);
        return location;
    }

    private static String locationKey(Map<String, Object> payload) {
        if (payload == null) return null;
        Map<String, Object> site = asMap(payload.get('site'));
        Map<String, Object> space = asMap(payload.get('space'));
        String siteCode = firstString(site == null ? null : site.get('code'), payload.get('siteCode'));
        String spaceCode = firstString(space == null ? null : space.get('code'), payload.get('spaceCode'));
        if (String.isBlank(siteCode) && String.isBlank(spaceCode)) return null;
        return (String.isBlank(siteCode) ? 'NONE' : siteCode) + '|' + (String.isBlank(spaceCode) ? 'NONE' : spaceCode);
    }

    private static Map<String, Object> mergeLocationPayload(
        Map<String, Object> current,
        Map<String, Object> incoming
    ) {
        if (current == null) return incoming;
        Map<String, Object> merged = new Map<String, Object>();
        merged.putAll(current);
        for (String key : incoming.keySet()) {
            Object incomingValue = incoming.get(key);
            Object currentValue = merged.get(key);
            if (incomingValue != null && (currentValue == null || String.isBlank(asString(currentValue)))) {
                merged.put(key, incomingValue);
            }
        }
        return merged;
    }

    private static String nestedName(Map<String, Object> payload, String localizedKey) {
        return firstString(
            payload == null ? null : payload.get(localizedKey),
            payload == null ? null : payload.get('name')
        );
    }

    private static String firstString(Object firstValue, Object secondValue) {
        return firstString(firstValue, secondValue, null);
    }

    private static String firstString(Object firstValue, Object secondValue, Object thirdValue) {
        String value = asString(firstValue);
        if (!String.isBlank(value)) return value;
        value = asString(secondValue);
        return !String.isBlank(value) ? value : asString(thirdValue);
    }

    private static Object firstObject(Object firstValue, Object secondValue) {
        return firstValue == null ? secondValue : firstValue;
    }

    private static Object firstObject(Object firstValue, Object secondValue, Object thirdValue) {
        return firstValue != null ? firstValue : (secondValue != null ? secondValue : thirdValue);
    }
    private static String preferredName(Map<String, Object> payload, String directKey, String translatedKey, String locale) {
        String direct = asString(payload.get(directKey));
        return String.isBlank(direct) ? translatedValue(payload.get(translatedKey), locale) : direct;
    }
    private static String translatedValue(Object rawValue, String locale) {
        Map<String, Object> value = asMap(rawValue);
        List<Object> translations = value == null ? null : asList(value.get('translations'));
        String fallback;
        if (translations != null) for (Object rawTranslation : translations) {
            Map<String, Object> translation = asMap(rawTranslation);
            String translated = translation == null ? null : asString(translation.get('value'));
            if (String.isBlank(translated)) continue;
            if (asString(translation.get('locale')) == locale) return translated;
            if (fallback == null) fallback = translated;
        }
        return fallback;
    }
    private static Map<String, Object> asMap(Object value) { return value instanceof Map<String, Object> ? (Map<String, Object>) value : null; }
    private static List<Object> asList(Object value) { return value instanceof List<Object> ? (List<Object>) value : null; }
    private static Decimal asDecimal(Object value) { if (value == null) return null; try { return Decimal.valueOf(String.valueOf(value)); } catch (Exception ignored) { return null; } }
    private static String asString(Object value) { return value == null ? null : String.valueOf(value); }
    private static String idKey(Object value) { Decimal numeric = asDecimal(value); return numeric == null ? asString(value) : numeric.setScale(0).toPlainString(); }
    private static String numberKey(Decimal value) { return value == null ? null : value.setScale(0).toPlainString(); }
    private static String numberKey(String value) { return value; }
    private static String truncate(String value, Integer limitValue) { return value == null || value.length() <= limitValue ? value : value.substring(0, limitValue); }
}
