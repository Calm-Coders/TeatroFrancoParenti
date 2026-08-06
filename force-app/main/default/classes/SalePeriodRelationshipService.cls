public without sharing class SalePeriodRelationshipService {
    private static final Integer LONG_TEXT_LIMIT = 32768;

    public class Stats {
        public Integer salesChannelsUpserted = 0;
        public Integer salePeriodsUpserted = 0;
        public Integer salePeriodsDeleted = 0;
        public Integer audienceRestrictionsInserted = 0;
        public Integer seatRestrictionsInserted = 0;
    }

    private class PeriodInput {
        public String relationshipKey;
        public Id inventoryId;
        public Id performanceId;
        public Integer sequence;
        public Map<String, Object> payload;
        public String channelKey;
    }

    public static Stats syncInventoryPayloads(
        List<InventoryWrapper> products,
        List<Inventory__c> inventories,
        List<Performance__c> performances
    ) {
        List<PeriodInput> inputs = new List<PeriodInput>();
        Set<Id> inventoryIds = new Set<Id>();
        Set<Id> performanceIds = new Set<Id>();
        Map<Id, Id> inventoryIdByEventId = new Map<Id, Id>();
        Set<Id> eventIds = new Set<Id>();
        for (Performance__c performance : performances) {
            if (performance.Inventory_Event__c != null) {
                eventIds.add(performance.Inventory_Event__c);
            }
        }
        if (!eventIds.isEmpty()) {
            for (Inventory_Event__c eventRecord : [
                SELECT Id, Inventory__c FROM Inventory_Event__c WHERE Id IN :eventIds
            ]) {
                inventoryIdByEventId.put(eventRecord.Id, eventRecord.Inventory__c);
            }
        }

        Map<String, Performance__c> performanceByOwnerAndExternalId =
            new Map<String, Performance__c>();
        for (Performance__c performance : performances) {
            Id inventoryId = inventoryIdByEventId.get(performance.Inventory_Event__c);
            if (inventoryId != null && performance.Performance_Id__c != null) {
                performanceByOwnerAndExternalId.put(
                    String.valueOf(inventoryId) + '|' + numberKey(performance.Performance_Id__c),
                    performance
                );
                performanceIds.add(performance.Id);
            }
        }

        for (Integer productIndex = 0; productIndex < products.size(); productIndex++) {
            InventoryWrapper product = products[productIndex];
            Inventory__c inventory = inventories[productIndex];
            inventoryIds.add(inventory.Id);
            addPeriods(inputs, inventory.Id, null, product.salePeriods, 'Inventory');

            Map<String, Object> eventPayload = asMap(product.event);
            List<Object> rawPerformances = eventPayload == null
                ? null : asList(eventPayload.get('performances'));
            if (rawPerformances == null) {
                continue;
            }
            for (Object rawPerformance : rawPerformances) {
                Map<String, Object> performancePayload = asMap(rawPerformance);
                Decimal externalId = performancePayload == null
                    ? null : asDecimal(performancePayload.get('id'));
                Performance__c performance = externalId == null ? null :
                    performanceByOwnerAndExternalId.get(
                        String.valueOf(inventory.Id) + '|' + numberKey(externalId)
                    );
                if (performance != null) {
                    addPeriods(
                        inputs,
                        null,
                        performance.Id,
                        performancePayload.get('salePeriods'),
                        'Performance'
                    );
                }
            }
        }
        return sync(inputs, inventoryIds, performanceIds);
    }

    public static Stats syncEnrichment(Map<Id, Map<String, Object>> productsByInventoryId) {
        List<PeriodInput> inputs = new List<PeriodInput>();
        Set<Id> inventoryIds = new Set<Id>(productsByInventoryId.keySet());
        Set<Id> performanceIds = new Set<Id>();
        Map<Id, Decimal> productIdByInventoryId = new Map<Id, Decimal>();
        for (Inventory__c inventory : [
            SELECT Id, Inventory_Id__c FROM Inventory__c WHERE Id IN :inventoryIds
        ]) {
            productIdByInventoryId.put(inventory.Id, inventory.Inventory_Id__c);
        }

        Map<String, Performance__c> performanceByOwnerAndExternalId =
            new Map<String, Performance__c>();
        for (Performance__c performance : [
            SELECT Id, Performance_Id__c, Inventory_Event__r.Inventory__c
            FROM Performance__c
            WHERE Inventory_Event__r.Inventory__c IN :inventoryIds
        ]) {
            Id inventoryId = performance.Inventory_Event__r.Inventory__c;
            performanceByOwnerAndExternalId.put(
                String.valueOf(inventoryId) + '|' + numberKey(performance.Performance_Id__c),
                performance
            );
        }

        for (Id inventoryId : inventoryIds) {
            Map<String, Object> product = productsByInventoryId.get(inventoryId);
            addPeriods(inputs, inventoryId, null, product.get('salePeriods'), 'Inventory');
            List<Object> rawPerformances = asList(product.get('performances'));
            if (rawPerformances == null) {
                continue;
            }
            for (Object rawPerformance : rawPerformances) {
                Map<String, Object> performancePayload = asMap(rawPerformance);
                Decimal externalId = performancePayload == null
                    ? null : asDecimal(performancePayload.get('id'));
                Performance__c performance = externalId == null ? null :
                    performanceByOwnerAndExternalId.get(
                        String.valueOf(inventoryId) + '|' + numberKey(externalId)
                    );
                if (performance != null) {
                    performanceIds.add(performance.Id);
                    addPeriods(
                        inputs,
                        null,
                        performance.Id,
                        performancePayload.get('salePeriods'),
                        'Performance'
                    );
                }
            }
        }
        return sync(inputs, inventoryIds, performanceIds);
    }

    public static void deleteForPerformances(List<Performance__c> performances) {
        Set<Id> performanceIds = new Set<Id>();
        for (Performance__c performance : performances) {
            if (performance.Id != null) {
                performanceIds.add(performance.Id);
            }
        }
        if (!performanceIds.isEmpty()) {
            delete [SELECT Id FROM Sale_Period__c WHERE Performance__c IN :performanceIds];
        }
    }

    private static Stats sync(
        List<PeriodInput> inputs,
        Set<Id> inventoryIds,
        Set<Id> performanceIds
    ) {
        Stats stats = new Stats();
        Map<String, Sales_Channel__c> channelByKey = new Map<String, Sales_Channel__c>();
        for (PeriodInput input : inputs) {
            Sales_Channel__c channel = buildChannel(input.payload);
            if (channel != null) {
                input.channelKey = channel.Channel_Key__c;
                channelByKey.put(channel.Channel_Key__c, channel);
            }
        }
        List<Sales_Channel__c> channels = channelByKey.values();
        if (!channels.isEmpty()) {
            upsert channels Channel_Key__c;
            stats.salesChannelsUpserted = channels.size();
        }
        channelByKey.clear();
        for (Sales_Channel__c channel : channels) {
            channelByKey.put(channel.Channel_Key__c, channel);
        }

        Map<String, PeriodInput> inputByKey = new Map<String, PeriodInput>();
        List<Sale_Period__c> periods = new List<Sale_Period__c>();
        for (PeriodInput input : inputs) {
            Sales_Channel__c channel = channelByKey.get(input.channelKey);
            periods.add(new Sale_Period__c(
                Relationship_Key__c = input.relationshipKey,
                Inventory__c = input.inventoryId,
                Performance__c = input.performanceId,
                Parent_Type__c = input.performanceId == null ? 'Inventory' : 'Performance',
                Sequence__c = input.sequence,
                Start__c = asDatetime(input.payload.get('start')),
                End__c = asDatetime(input.payload.get('end')),
                End_Relative__c = truncate(jsonOrString(input.payload.get('endRelative')), 255),
                Sales_Channel__c = channel == null ? null : channel.Id,
                Type__c = truncate(asString(input.payload.get('type')), 80),
                Sale_Possible__c = asBoolean(input.payload.get('salePossible')) == true,
                Reservation_Possible__c = asBoolean(input.payload.get('reservationPossible')) == true,
                Quotation_Possible__c = asBoolean(input.payload.get('quotationPossible')) == true,
                Posting_Resale_Possible__c = asBoolean(input.payload.get('postingResalePossible')) == true,
                Raw_JSON__c = truncate(JSON.serialize(input.payload), LONG_TEXT_LIMIT)
            ));
            inputByKey.put(input.relationshipKey, input);
        }
        if (!periods.isEmpty()) {
            upsert periods Relationship_Key__c;
            stats.salePeriodsUpserted = periods.size();
        }

        Set<String> desiredKeys = inputByKey.keySet();
        Map<Id, Sale_Period__c> existingById = new Map<Id, Sale_Period__c>();
        if (!inventoryIds.isEmpty()) {
            existingById.putAll([
                SELECT Id, Relationship_Key__c
                FROM Sale_Period__c WHERE Inventory__c IN :inventoryIds
            ]);
        }
        if (!performanceIds.isEmpty()) {
            existingById.putAll([
                SELECT Id, Relationship_Key__c
                FROM Sale_Period__c WHERE Performance__c IN :performanceIds
            ]);
        }
        List<Sale_Period__c> stale = new List<Sale_Period__c>();
        for (Sale_Period__c existing : existingById.values()) {
            if (!desiredKeys.contains(existing.Relationship_Key__c)) {
                stale.add(existing);
            }
        }
        if (!stale.isEmpty()) {
            delete stale;
            stats.salePeriodsDeleted = stale.size();
        }

        Set<Id> desiredPeriodIds = new Set<Id>();
        for (Sale_Period__c period : periods) {
            desiredPeriodIds.add(period.Id);
        }
        if (!desiredPeriodIds.isEmpty()) {
            delete [
                SELECT Id FROM Sale_Period_Audience__c
                WHERE Sale_Period__c IN :desiredPeriodIds
            ];
            delete [
                SELECT Id FROM Sale_Period_Seat_Category__c
                WHERE Sale_Period__c IN :desiredPeriodIds
            ];
        }

        List<Sale_Period_Audience__c> audiences = new List<Sale_Period_Audience__c>();
        List<Sale_Period_Seat_Category__c> seats = new List<Sale_Period_Seat_Category__c>();
        for (Sale_Period__c period : periods) {
            PeriodInput input = inputByKey.get(period.Relationship_Key__c);
            audiences.addAll(buildAudienceRestrictions(period.Id, input.payload));
            seats.addAll(buildSeatRestrictions(period.Id, input.payload));
        }
        if (!audiences.isEmpty()) {
            insert audiences;
            stats.audienceRestrictionsInserted = audiences.size();
        }
        if (!seats.isEmpty()) {
            insert seats;
            stats.seatRestrictionsInserted = seats.size();
        }
        return stats;
    }

    private static void addPeriods(
        List<PeriodInput> inputs,
        Id inventoryId,
        Id performanceId,
        Object rawPeriods,
        String parentType
    ) {
        List<Object> periods = asList(rawPeriods);
        if (periods == null) {
            return;
        }
        for (Integer index = 0; index < periods.size(); index++) {
            Map<String, Object> payload = asMap(periods[index]);
            if (payload == null) {
                continue;
            }
            PeriodInput input = new PeriodInput();
            input.inventoryId = inventoryId;
            input.performanceId = performanceId;
            input.sequence = index;
            input.payload = payload;
            input.relationshipKey = parentType.substring(0, 1) + '|' +
                String.valueOf(performanceId == null ? inventoryId : performanceId) + '|' + index;
            inputs.add(input);
        }
    }

    private static Sales_Channel__c buildChannel(Map<String, Object> period) {
        Map<String, Object> nested = asMap(period.get('salesChannel'));
        Decimal channelId = asDecimal(
            nested == null ? period.get('salesChannelId') : nested.get('id')
        );
        String code = asString(
            nested == null ? period.get('salesChannelCode') : nested.get('code')
        );
        String key = channelId != null ? 'ID|' + numberKey(channelId) :
            (String.isBlank(code) ? null : 'CODE|' + code);
        if (key == null) {
            return null;
        }
        String nameIt = nested == null ? null : firstValue(nested, 'name_it', 'name');
        String nameEn = nested == null ? null : firstValue(nested, 'name_en', 'name');
        String displayName = !String.isBlank(nameIt) ? nameIt :
            (!String.isBlank(code) ? code : key);
        return new Sales_Channel__c(
            Name = truncate(displayName, 80),
            Channel_Key__c = key,
            Channel_Id__c = channelId,
            Code__c = truncate(code, 80),
            Name_IT__c = truncate(nameIt, 255),
            Name_EN__c = truncate(nameEn, 255)
        );
    }

    private static List<Sale_Period_Audience__c> buildAudienceRestrictions(
        Id periodId,
        Map<String, Object> payload
    ) {
        Map<String, Sale_Period_Audience__c> byKey = new Map<String, Sale_Period_Audience__c>();
        addAudienceValues(byKey, periodId, asList(payload.get('audienceSubCatIds')));
        addAudienceValues(byKey, periodId, asList(payload.get('tariffs')));
        addAudienceValues(byKey, periodId, asList(payload.get('ticketTypes')));
        return byKey.values();
    }

    private static void addAudienceValues(
        Map<String, Sale_Period_Audience__c> byKey,
        Id periodId,
        List<Object> values
    ) {
        if (values == null) {
            return;
        }
        for (Object value : values) {
            Map<String, Object> item = asMap(value);
            Decimal externalId = asDecimal(item == null ? value : item.get('id'));
            String code = item == null ? null : asString(item.get('code'));
            String key = externalId != null ? numberKey(externalId) : code;
            if (String.isBlank(key)) {
                continue;
            }
            byKey.put(key, new Sale_Period_Audience__c(
                Sale_Period__c = periodId,
                Audience_Subcategory_Id__c = externalId,
                Code__c = truncate(code, 80),
                Name_IT__c = truncate(item == null ? null : firstValue(item, 'name_it', 'name'), 255),
                Kind__c = truncate(item == null ? null : asString(item.get('kind')), 80)
            ));
        }
    }

    private static List<Sale_Period_Seat_Category__c> buildSeatRestrictions(
        Id periodId,
        Map<String, Object> payload
    ) {
        Map<String, Sale_Period_Seat_Category__c> byKey =
            new Map<String, Sale_Period_Seat_Category__c>();
        addSeatValues(byKey, periodId, asList(payload.get('seatCategoryIds')));
        addSeatValues(byKey, periodId, asList(payload.get('seatCategories')));
        return byKey.values();
    }

    private static void addSeatValues(
        Map<String, Sale_Period_Seat_Category__c> byKey,
        Id periodId,
        List<Object> values
    ) {
        if (values == null) {
            return;
        }
        for (Object value : values) {
            Map<String, Object> item = asMap(value);
            Decimal externalId = asDecimal(item == null ? value : item.get('id'));
            String code = item == null ? null : asString(item.get('code'));
            String key = externalId != null ? numberKey(externalId) : code;
            if (String.isBlank(key)) {
                continue;
            }
            byKey.put(key, new Sale_Period_Seat_Category__c(
                Sale_Period__c = periodId,
                Seat_Category_Id__c = externalId,
                Code__c = truncate(code, 80),
                Name_IT__c = truncate(item == null ? null : firstValue(item, 'name_it', 'name'), 255)
            ));
        }
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
        if (value == null) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception error) {
            return null;
        }
    }

    private static Boolean asBoolean(Object value) {
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return value == null ? null : 'true'.equalsIgnoreCase(String.valueOf(value));
    }

    private static Datetime asDatetime(Object value) {
        if (value == null) {
            return null;
        }
        Decimal numeric = asDecimal(value);
        if (numeric != null) {
            try {
                Long epochMillis = Long.valueOf(String.valueOf(numeric.setScale(0)));
                return Datetime.newInstanceGmt(1970, 1, 1, 0, 0, 0)
                    .addSeconds(Integer.valueOf(String.valueOf(epochMillis / 1000)));
            } catch (Exception ignored) {
                return null;
            }
        }
        String text = asString(value);
        if (String.isBlank(text) || text.length() < 19) {
            return null;
        }
        try {
            return Datetime.valueOf(text.substring(0, 19).replace('T', ' '));
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String firstValue(Map<String, Object> source, String primary, String fallback) {
        String value = asString(source.get(primary));
        return String.isBlank(value) ? asString(source.get(fallback)) : value;
    }

    private static String jsonOrString(Object value) {
        if (value == null) {
            return null;
        }
        return value instanceof Map<String, Object> || value instanceof List<Object>
            ? JSON.serialize(value) : asString(value);
    }

    private static String numberKey(Decimal value) {
        return value == null ? '' : String.valueOf(value.setScale(0));
    }

    private static String truncate(String value, Integer length) {
        return value == null || value.length() <= length ? value : value.substring(0, length);
    }
}
