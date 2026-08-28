public without sharing class PerformancePriceRelationshipService {
    private static final Integer LONG_TEXT_LIMIT = 32768;
    private static final Decimal SECUTIX_AMOUNT_SCALE = 1000;

    public class Stats {
        public Integer audiencesUpserted = 0;
        public Integer salePeriodAudiencesLinked = 0;
        public Integer seatCategoriesUpserted = 0;
        public Integer pricesUpserted = 0;
        public Integer pricesDeleted = 0;
        public Integer chargeComponentsUpserted = 0;
        public Integer priceChargesUpserted = 0;
        public Integer priceChargesDeleted = 0;
    }

    private class PriceInput {
        public Id performanceId;
        public List<Object> prices;
        public Boolean rawCents;
        public List<Object> audienceLegends = new List<Object>();
    }

    private class PriceDetails {
        public String priceKey;
        public Id performanceId;
        public Map<String, Object> payload;
        public Boolean rawCents;
        public String seatKey;
        public String audienceKey;
        public Decimal seatId;
        public Decimal institutionSeatId;
        public Decimal audienceId;
        public List<Object> charges;
        public Boolean chargeAmountsAreRawCents;
        public Integer sequence;
    }

    private class ReferenceResult {
        public Integer upserted = 0;
        public Map<String, Audience_Sub_Category__c> audiences = new Map<String, Audience_Sub_Category__c>();
        public Map<String, Charge_Component__c> charges = new Map<String, Charge_Component__c>();
    }

    public static Stats syncInventoryPayloads(
        List<InventoryWrapper> products,
        List<Inventory__c> inventories,
        List<Performance__c> performances
    ) {
        Set<Id> inventoryIds = new Set<Id>();
        Map<Id, Id> inventoryIdByEventId = inventoryIdByEvent(performances);
        Map<String, Performance__c> performanceByOwnerAndExternalId =
            performanceByOwnerAndExternalId(performances, inventoryIdByEventId);
        Map<Id, PriceInput> inputs = new Map<Id, PriceInput>();

        for (Integer productIndex = 0; productIndex < products.size(); productIndex++) {
            InventoryWrapper product = products[productIndex];
            Inventory__c inventory = inventories[productIndex];
            inventoryIds.add(inventory.Id);
            Map<String, Object> eventPayload = asMap(product.event);
            List<Object> rawPerformances = eventPayload == null ? null : asList(eventPayload.get('performances'));
            if (rawPerformances == null) continue;
            for (Object rawPerformance : rawPerformances) {
                Map<String, Object> payload = asMap(rawPerformance);
                Decimal externalId = payload == null ? null : asDecimal(payload.get('id'));
                Performance__c performance = externalId == null ? null : performanceByOwnerAndExternalId.get(
                    String.valueOf(inventory.Id) + '|' + numberKey(externalId)
                );
                if (performance == null || !payload.containsKey('prices')) continue;
                PriceInput input = new PriceInput();
                input.performanceId = performance.Id;
                input.prices = asList(payload.get('prices'));
                if (input.prices == null) input.prices = new List<Object>();
                input.rawCents = true;
                inputs.put(performance.Id, input);
            }
        }
        return sync(inputs, inventoryIds, new List<Object>());
    }

    public static Stats syncEnrichment(Map<Id, Map<String, Object>> productsByInventoryId) {
        Set<Id> inventoryIds = new Set<Id>(productsByInventoryId.keySet());
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

        Map<Id, PriceInput> inputs = new Map<Id, PriceInput>();
        List<Object> globalLegends = new List<Object>();
        for (Id inventoryId : inventoryIds) {
            Map<String, Object> product = productsByInventoryId.get(inventoryId);
            List<Object> ticketTypes = asList(product.get('ticketTypes'));
            if (ticketTypes != null) globalLegends.addAll(ticketTypes);
            List<Object> rawPerformances = asList(product.get('performances'));
            if (rawPerformances == null) continue;
            for (Object rawPerformance : rawPerformances) {
                Map<String, Object> payload = asMap(rawPerformance);
                Decimal externalId = payload == null ? null : asDecimal(payload.get('id'));
                Performance__c performance = externalId == null ? null : performanceByOwnerAndExternalId.get(
                    String.valueOf(inventoryId) + '|' + numberKey(externalId)
                );
                if (performance == null) continue;
                Boolean hasRawPrices = payload.containsKey('prices');
                Boolean hasPriceGrid = payload.containsKey('priceGrid');
                if (!hasRawPrices && !hasPriceGrid) continue;
                PriceInput input = new PriceInput();
                input.performanceId = performance.Id;
                input.prices = asList(payload.get(hasPriceGrid ? 'priceGrid' : 'prices'));
                if (input.prices == null) input.prices = new List<Object>();
                input.rawCents = !hasPriceGrid;
                if (ticketTypes != null) input.audienceLegends.addAll(ticketTypes);
                inputs.put(performance.Id, input);
            }
        }
        return sync(inputs, inventoryIds, globalLegends);
    }

    public static Stats syncStoredPerformances(List<Performance__c> performances) {
        Map<Id, PriceInput> inputs = new Map<Id, PriceInput>();
        for (Performance__c performance : performances) {
            if (performance.Id == null || String.isBlank(performance.Prices__c)) continue;
            try {
                PriceInput input = new PriceInput();
                input.performanceId = performance.Id;
                input.prices = asList(JSON.deserializeUntyped(performance.Prices__c));
                if (input.prices == null) input.prices = new List<Object>();
                input.rawCents = true;
                if (!String.isBlank(performance.Tariff_Legend__c)) {
                    List<Object> legends = asList(JSON.deserializeUntyped(performance.Tariff_Legend__c));
                    if (legends != null) input.audienceLegends.addAll(legends);
                }
                inputs.put(performance.Id, input);
            } catch (Exception ignored) {
                // Keep malformed historical JSON as audit data and skip only that Performance.
            }
        }
        return sync(inputs, new Set<Id>(), new List<Object>());
    }

    public static Stats syncStoredSalePeriodAudiences(List<Sale_Period_Audience__c> restrictions) {
        Stats stats = new Stats();
        if (restrictions == null || restrictions.isEmpty()) return stats;
        Map<String, Map<String, Object>> payloadByKey = new Map<String, Map<String, Object>>();
        for (Sale_Period_Audience__c restriction : restrictions) {
            Map<String, Object> payload = audiencePayload(restriction);
            String key = audienceKey(payload);
            if (!String.isBlank(key)) payloadByKey.put(key, payload);
        }
        ReferenceResult refs = upsertAudiences(payloadByKey);
        stats.audiencesUpserted = refs.upserted;
        List<Sale_Period_Audience__c> updates = new List<Sale_Period_Audience__c>();
        for (Sale_Period_Audience__c restriction : restrictions) {
            String key = audienceKey(audiencePayload(restriction));
            Audience_Sub_Category__c audience = refs.audiences.get(key);
            if (audience != null && restriction.Audience_Sub_Category__c != audience.Id) {
                updates.add(new Sale_Period_Audience__c(Id = restriction.Id, Audience_Sub_Category__c = audience.Id));
            }
        }
        if (!updates.isEmpty()) update updates;
        stats.salePeriodAudiencesLinked = updates.size();
        return stats;
    }

    private static Stats sync(
        Map<Id, PriceInput> inputs,
        Set<Id> inventoryIds,
        List<Object> globalAudienceLegends
    ) {
        Stats stats = new Stats();
        Set<Id> performanceIds = inputs.keySet();
        List<Sale_Period_Audience__c> salePeriodAudiences = new List<Sale_Period_Audience__c>();
        if (!inventoryIds.isEmpty() || !performanceIds.isEmpty()) {
            salePeriodAudiences = [
                SELECT Id, Audience_Subcategory_Id__c, Code__c, Name_IT__c, Kind__c,
                       Audience_Sub_Category__c
                FROM Sale_Period_Audience__c
                WHERE Sale_Period__r.Inventory__c IN :inventoryIds
                   OR Sale_Period__r.Performance__c IN :performanceIds
            ];
        }

        Map<String, Map<String, Object>> audiencePayloadByKey = new Map<String, Map<String, Object>>();
        addAudiencePayloads(audiencePayloadByKey, globalAudienceLegends);
        for (PriceInput input : inputs.values()) addAudiencePayloads(audiencePayloadByKey, input.audienceLegends);
        for (Sale_Period_Audience__c restriction : salePeriodAudiences) {
            putRicherAudience(audiencePayloadByKey, audiencePayload(restriction));
        }

        List<PriceDetails> details = new List<PriceDetails>();
        Set<String> seatKeys = new Set<String>();
        for (PriceInput input : inputs.values()) {
            Map<String, Integer> occurrenceByBaseKey = new Map<String, Integer>();
            for (Integer sequence = 0; sequence < input.prices.size(); sequence++) {
                Map<String, Object> payload = asMap(input.prices[sequence]);
                if (payload == null) continue;
                PriceDetails item = priceDetails(input, payload, sequence);
                if (!String.isBlank(item.seatKey)) seatKeys.add(item.seatKey);
                Map<String, Object> audiencePayload = extractAudiencePayload(payload, input.rawCents);
                putRicherAudience(audiencePayloadByKey, audiencePayload);
                String baseKey = String.valueOf(input.performanceId) + '|' + nullKey(item.seatKey) + '|' + nullKey(item.audienceKey);
                Integer occurrence = occurrenceByBaseKey.containsKey(baseKey) ? occurrenceByBaseKey.get(baseKey) : 0;
                occurrenceByBaseKey.put(baseKey, occurrence + 1);
                item.priceKey = occurrence == 0 ? baseKey : baseKey + '|DUP:' + String.valueOf(occurrence);
                details.add(item);
            }
        }

        ReferenceResult audienceRefs = upsertAudiences(audiencePayloadByKey);
        stats.audiencesUpserted = audienceRefs.upserted;
        List<Sale_Period_Audience__c> salePeriodUpdates = new List<Sale_Period_Audience__c>();
        for (Sale_Period_Audience__c restriction : salePeriodAudiences) {
            String key = audienceKey(audiencePayload(restriction));
            Audience_Sub_Category__c audience = audienceRefs.audiences.get(key);
            if (audience != null && restriction.Audience_Sub_Category__c != audience.Id) {
                salePeriodUpdates.add(new Sale_Period_Audience__c(Id = restriction.Id, Audience_Sub_Category__c = audience.Id));
            }
        }
        if (!salePeriodUpdates.isEmpty()) update salePeriodUpdates;
        stats.salePeriodAudiencesLinked = salePeriodUpdates.size();

        Map<String, Seat_Category__c> seatByKey = new Map<String, Seat_Category__c>();
        if (!seatKeys.isEmpty()) {
            for (Seat_Category__c seat : [
                SELECT Id, Category_Key__c FROM Seat_Category__c WHERE Category_Key__c IN :seatKeys
            ]) seatByKey.put(seat.Category_Key__c, seat);
            List<Seat_Category__c> missingSeats = new List<Seat_Category__c>();
            for (String key : seatKeys) {
                if (!seatByKey.containsKey(key)) {
                    Decimal externalId = key.startsWith('CODE:') ? null : asDecimal(key);
                    missingSeats.add(new Seat_Category__c(
                        Name = truncate('Seat Category ' + key, 80), Category_Key__c = key,
                        Seat_Category_Id__c = numberKey(externalId)
                    ));
                }
            }
            if (!missingSeats.isEmpty()) {
                upsert missingSeats Category_Key__c;
                stats.seatCategoriesUpserted = missingSeats.size();
                for (Seat_Category__c seat : missingSeats) seatByKey.put(seat.Category_Key__c, seat);
            }
        }

        List<Performance_Price__c> prices = new List<Performance_Price__c>();
        Set<String> desiredPriceKeys = new Set<String>();
        Map<String, PriceDetails> detailsByPriceKey = new Map<String, PriceDetails>();
        for (PriceDetails item : details) {
            desiredPriceKeys.add(item.priceKey);
            detailsByPriceKey.put(item.priceKey, item);
            prices.add(new Performance_Price__c(
                Price_Key__c = item.priceKey,
                Performance__c = item.performanceId,
                Seat_Category__c = item.seatKey == null || seatByKey.get(item.seatKey) == null
                    ? null : seatByKey.get(item.seatKey).Id,
                Audience_Sub_Category__c = item.audienceKey == null || audienceRefs.audiences.get(item.audienceKey) == null
                    ? null : audienceRefs.audiences.get(item.audienceKey).Id,
                Seat_Category_Id__c = numberKey(item.seatId),
                Institution_Seat_Category_Id__c = numberKey(item.institutionSeatId),
                Audience_Subcategory_Id__c = numberKey(item.audienceId),
                Amount__c = money(item.payload.get('amount')),
                Min_Quantity__c = firstDecimal(item.payload, new List<String>{ 'minQty', 'minQuantity' }),
                Max_Quantity__c = firstDecimal(item.payload, new List<String>{ 'maxQty', 'maxQuantity' }),
                Sequence__c = item.sequence,
                Raw_JSON__c = truncate(JSON.serialize(item.payload), LONG_TEXT_LIMIT)
            ));
        }
        if (!prices.isEmpty()) {
            upsert prices Price_Key__c;
            stats.pricesUpserted = prices.size();
        }
        Map<String, Performance_Price__c> priceByKey = new Map<String, Performance_Price__c>();
        for (Performance_Price__c price : prices) priceByKey.put(price.Price_Key__c, price);

        Map<String, Map<String, Object>> chargePayloadByKey = new Map<String, Map<String, Object>>();
        for (PriceDetails item : details) addChargePayloads(chargePayloadByKey, item.charges);
        ReferenceResult chargeRefs = upsertCharges(chargePayloadByKey);
        stats.chargeComponentsUpserted = chargeRefs.upserted;

        List<Performance_Price_Charge__c> priceCharges = new List<Performance_Price_Charge__c>();
        Set<String> desiredChargeKeys = new Set<String>();
        for (PriceDetails item : details) {
            Performance_Price__c price = priceByKey.get(item.priceKey);
            if (price == null || item.charges == null) continue;
            Map<String, Integer> occurrences = new Map<String, Integer>();
            for (Integer sequence = 0; sequence < item.charges.size(); sequence++) {
                Map<String, Object> payload = asMap(item.charges[sequence]);
                String chargeKey = chargeKey(payload);
                if (payload == null || String.isBlank(chargeKey)) continue;
                Integer occurrence = occurrences.containsKey(chargeKey) ? occurrences.get(chargeKey) : 0;
                occurrences.put(chargeKey, occurrence + 1);
                String relationshipKey = item.priceKey + '|' + chargeKey + (occurrence == 0 ? '' : '|DUP:' + occurrence);
                desiredChargeKeys.add(relationshipKey);
                Charge_Component__c component = chargeRefs.charges.get(chargeKey);
                priceCharges.add(new Performance_Price_Charge__c(
                    Relationship_Key__c = relationshipKey,
                    Performance_Price__c = price.Id,
                    Charge_Component__c = component == null ? null : component.Id,
                    Charge_Id__c = numberKey(firstDecimal(payload, new List<String>{ 'chargesId', 'chargeId', 'id' })),
                    Component_Code__c = truncate(firstString(payload, new List<String>{ 'component', 'code' }), 80),
                    Amount__c = money(payload.get('amount')),
                    Sequence__c = sequence,
                    Raw_JSON__c = truncate(JSON.serialize(payload), LONG_TEXT_LIMIT)
                ));
            }
        }
        if (!priceCharges.isEmpty()) {
            upsert priceCharges Relationship_Key__c;
            stats.priceChargesUpserted = priceCharges.size();
        }

        if (!performanceIds.isEmpty()) {
            List<Performance_Price_Charge__c> staleCharges = new List<Performance_Price_Charge__c>();
            for (Performance_Price_Charge__c existing : [
                SELECT Id, Relationship_Key__c FROM Performance_Price_Charge__c
                WHERE Performance_Price__r.Performance__c IN :performanceIds
            ]) {
                if (!desiredChargeKeys.contains(existing.Relationship_Key__c)) staleCharges.add(existing);
            }
            if (!staleCharges.isEmpty()) delete staleCharges;
            stats.priceChargesDeleted = staleCharges.size();

            List<Performance_Price__c> stalePrices = new List<Performance_Price__c>();
            for (Performance_Price__c existing : [
                SELECT Id, Price_Key__c FROM Performance_Price__c WHERE Performance__c IN :performanceIds
            ]) {
                if (!desiredPriceKeys.contains(existing.Price_Key__c)) stalePrices.add(existing);
            }
            if (!stalePrices.isEmpty()) delete stalePrices;
            stats.pricesDeleted = stalePrices.size();
        }
        return stats;
    }

    private static PriceDetails priceDetails(PriceInput input, Map<String, Object> payload, Integer sequence) {
        PriceDetails item = new PriceDetails();
        item.performanceId = input.performanceId;
        item.payload = payload;
        item.rawCents = input.rawCents;
        item.sequence = sequence;
        Map<String, Object> seat = input.rawCents ? null : asMap(payload.get('seatCategory'));
        Map<String, Object> audience = extractAudiencePayload(payload, input.rawCents);
        item.seatId = input.rawCents ? asDecimal(payload.get('seatCatId')) : asDecimal(seat == null ? null : seat.get('id'));
        item.institutionSeatId = firstDecimal(payload, new List<String>{ 'institutionSeatCatId', 'institutionSeatCategoryId' });
        item.audienceId = asDecimal(audience == null ? null : audience.get('id'));
        item.seatKey = referenceKey(item.seatId, seat == null ? null : asString(seat.get('code')));
        item.audienceKey = audienceKey(audience);
        item.charges = asList(payload.get(input.rawCents ? 'chargesAmounts' : 'fees'));
        if (item.charges == null) item.charges = new List<Object>();
        item.chargeAmountsAreRawCents = input.rawCents;
        return item;
    }

    private static Map<String, Object> extractAudiencePayload(Map<String, Object> price, Boolean rawCents) {
        if (price == null) return null;
        if (!rawCents) return asMap(price.get('tariff'));
        Decimal idValue = asDecimal(price.get('audSubCatId'));
        return idValue == null ? null : new Map<String, Object>{ 'id' => idValue };
    }

    private static ReferenceResult upsertAudiences(Map<String, Map<String, Object>> payloadByKey) {
        ReferenceResult result = new ReferenceResult();
        if (payloadByKey.isEmpty()) return result;
        Set<String> audienceKeys = payloadByKey.keySet();
        for (Audience_Sub_Category__c existing : [
            SELECT Id, Audience_Key__c FROM Audience_Sub_Category__c WHERE Audience_Key__c IN :audienceKeys
        ]) result.audiences.put(existing.Audience_Key__c, existing);
        List<Audience_Sub_Category__c> records = new List<Audience_Sub_Category__c>();
        for (String key : payloadByKey.keySet()) {
            Map<String, Object> payload = payloadByKey.get(key);
            if (!result.audiences.containsKey(key) || isRichAudience(payload)) records.add(buildAudience(key, payload));
        }
        if (!records.isEmpty()) upsert records Audience_Key__c;
        result.upserted = records.size();
        for (Audience_Sub_Category__c recordItem : records) result.audiences.put(recordItem.Audience_Key__c, recordItem);
        return result;
    }

    private static ReferenceResult upsertCharges(Map<String, Map<String, Object>> payloadByKey) {
        ReferenceResult result = new ReferenceResult();
        if (payloadByKey.isEmpty()) return result;
        Set<String> chargeKeys = payloadByKey.keySet();
        for (Charge_Component__c existing : [
            SELECT Id, Charge_Key__c FROM Charge_Component__c WHERE Charge_Key__c IN :chargeKeys
        ]) result.charges.put(existing.Charge_Key__c, existing);
        List<Charge_Component__c> records = new List<Charge_Component__c>();
        for (String key : payloadByKey.keySet()) {
            Map<String, Object> payload = payloadByKey.get(key);
            if (!result.charges.containsKey(key) || !String.isBlank(firstString(payload, new List<String>{ 'component', 'code' }))) {
                String code = firstString(payload, new List<String>{ 'component', 'code' });
                records.add(new Charge_Component__c(
                    Name = truncate(String.isBlank(code) ? 'Charge ' + key : code, 80),
                    Charge_Key__c = key,
                    Charge_Id__c = numberKey(firstDecimal(payload, new List<String>{ 'chargesId', 'chargeId', 'id' })),
                    Code__c = truncate(code, 80),
                    Raw_JSON__c = truncate(JSON.serialize(payload), LONG_TEXT_LIMIT)
                ));
            }
        }
        if (!records.isEmpty()) upsert records Charge_Key__c;
        result.upserted = records.size();
        for (Charge_Component__c recordItem : records) result.charges.put(recordItem.Charge_Key__c, recordItem);
        return result;
    }

    private static Audience_Sub_Category__c buildAudience(String key, Map<String, Object> payload) {
        String nameIt = firstString(payload, new List<String>{ 'name_it', 'name' });
        if (String.isBlank(nameIt)) nameIt = translatedValue(payload.get('externalName'), 'it');
        String nameEn = firstString(payload, new List<String>{ 'name_en' });
        if (String.isBlank(nameEn)) nameEn = translatedValue(payload.get('externalName'), 'en');
        String code = asString(payload.get('code'));
        String displayName = !String.isBlank(nameIt) ? nameIt : (!String.isBlank(code) ? code : 'Audience ' + key);
        return new Audience_Sub_Category__c(
            Name = truncate(displayName, 80),
            Audience_Key__c = key,
            Audience_Subcategory_Id__c = numberKey(asDecimal(payload.get('id'))),
            Audience_Category_Id__c = numberKey(firstDecimal(payload, new List<String>{ 'audienceCategoryId', 'audienceCatId' })),
            Code__c = truncate(code, 80),
            Kind__c = truncate(firstString(payload, new List<String>{ 'kind', 'audienceCategoryKind', 'category_kind' }), 80),
            Rank__c = firstDecimal(payload, new List<String>{ 'rank', 'rank_number' }),
            Min_Quantity__c = firstDecimal(payload, new List<String>{ 'minQuantity', 'minQty' }),
            Max_Quantity__c = firstDecimal(payload, new List<String>{ 'maxQuantity', 'maxQty' }),
            Require_Attachment__c = asBoolean(payload.get('requireAttachment')) == true,
            Exchangeable__c = asBoolean(payload.get('exchangeable')) == true,
            Name_IT__c = truncate(nameIt, 255),
            Name_EN__c = truncate(nameEn, 255),
            Required_Audience_Ids__c = truncate(JSON.serialize(payload.get('requiredAudienceSubCategoryIds')), LONG_TEXT_LIMIT),
            Raw_JSON__c = truncate(JSON.serialize(payload), LONG_TEXT_LIMIT)
        );
    }

    private static Map<String, Object> audiencePayload(Sale_Period_Audience__c restriction) {
        return new Map<String, Object>{
            'id' => restriction.Audience_Subcategory_Id__c,
            'code' => restriction.Code__c,
            'name_it' => restriction.Name_IT__c,
            'kind' => restriction.Kind__c
        };
    }

    private static void addAudiencePayloads(Map<String, Map<String, Object>> target, List<Object> values) {
        if (values == null) return;
        for (Object rawValue : values) putRicherAudience(target, asMap(rawValue));
    }
    private static void putRicherAudience(Map<String, Map<String, Object>> target, Map<String, Object> payload) {
        String key = audienceKey(payload);
        if (String.isBlank(key)) return;
        if (!target.containsKey(key) || (!isRichAudience(target.get(key)) && isRichAudience(payload))) target.put(key, payload);
    }
    private static Boolean isRichAudience(Map<String, Object> payload) {
        return payload != null && (
            !String.isBlank(asString(payload.get('code'))) || !String.isBlank(asString(payload.get('name'))) ||
            !String.isBlank(asString(payload.get('name_it'))) || payload.get('externalName') != null ||
            !String.isBlank(asString(payload.get('kind'))) || !String.isBlank(asString(payload.get('audienceCategoryKind')))
        );
    }
    private static void addChargePayloads(Map<String, Map<String, Object>> target, List<Object> values) {
        if (values == null) return;
        for (Object rawValue : values) {
            Map<String, Object> payload = asMap(rawValue);
            String key = chargeKey(payload);
            if (!String.isBlank(key)) target.put(key, payload);
        }
    }

    private static Map<Id, Id> inventoryIdByEvent(List<Performance__c> performances) {
        Set<Id> eventIds = new Set<Id>();
        for (Performance__c performance : performances) if (performance.Inventory_Event__c != null) eventIds.add(performance.Inventory_Event__c);
        Map<Id, Id> result = new Map<Id, Id>();
        if (!eventIds.isEmpty()) for (Inventory_Event__c eventRecord : [SELECT Id, Inventory__c FROM Inventory_Event__c WHERE Id IN :eventIds]) result.put(eventRecord.Id, eventRecord.Inventory__c);
        return result;
    }
    private static Map<String, Performance__c> performanceByOwnerAndExternalId(List<Performance__c> performances, Map<Id, Id> inventoryIdByEventId) {
        Map<String, Performance__c> result = new Map<String, Performance__c>();
        for (Performance__c performance : performances) {
            Id inventoryId = inventoryIdByEventId.get(performance.Inventory_Event__c);
            if (inventoryId != null && performance.Performance_Id__c != null) result.put(String.valueOf(inventoryId) + '|' + numberKey(performance.Performance_Id__c), performance);
        }
        return result;
    }

    private static String audienceKey(Map<String, Object> payload) {
        if (payload == null) return null;
        return referenceKey(asDecimal(payload.get('id')), asString(payload.get('code')));
    }
    private static String chargeKey(Map<String, Object> payload) {
        if (payload == null) return null;
        Decimal idValue = firstDecimal(payload, new List<String>{ 'chargesId', 'chargeId', 'id' });
        return referenceKey(idValue, firstString(payload, new List<String>{ 'component', 'code' }));
    }
    private static String referenceKey(Decimal idValue, String code) {
        if (idValue != null) return numberKey(idValue);
        return String.isBlank(code) ? null : 'CODE:' + code;
    }
    private static String nullKey(String value) { return String.isBlank(value) ? 'NONE' : value; }

    private static Decimal money(Object value) {
        if (value == null) return null;
        if (value instanceof String) {
            String original = String.valueOf(value).trim();
            String cleaned = original.replaceAll('[^0-9,.-]', '');
            if (String.isBlank(cleaned)) return null;
            if (cleaned.contains(',') && cleaned.contains('.')) cleaned = cleaned.replace('.', '').replace(',', '.');
            else cleaned = cleaned.replace(',', '.');
            try {
                Decimal parsed = Decimal.valueOf(cleaned);
                Boolean explicitlyFormatted = original.contains('€') || original.contains('.') || original.contains(',');
                return explicitlyFormatted ? parsed : parsed / SECUTIX_AMOUNT_SCALE;
            } catch (Exception ignored) { return null; }
        }
        Decimal parsed = asDecimal(value);
        return parsed == null ? null : parsed / SECUTIX_AMOUNT_SCALE;
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
    private static Decimal firstDecimal(Map<String, Object> value, List<String> keys) {
        if (value == null) return null;
        for (String key : keys) { Decimal found = asDecimal(value.get(key)); if (found != null) return found; }
        return null;
    }
    private static String firstString(Map<String, Object> value, List<String> keys) {
        if (value == null) return null;
        for (String key : keys) { String found = asString(value.get(key)); if (!String.isBlank(found)) return found; }
        return null;
    }
    private static Map<String, Object> asMap(Object value) { return value instanceof Map<String, Object> ? (Map<String, Object>) value : null; }
    private static List<Object> asList(Object value) { return value instanceof List<Object> ? (List<Object>) value : null; }
    private static Decimal asDecimal(Object value) { if (value == null) return null; try { return Decimal.valueOf(String.valueOf(value)); } catch (Exception ignored) { return null; } }
    private static Boolean asBoolean(Object value) { if (value == null) return null; return String.valueOf(value).toLowerCase() == 'true'; }
    private static String asString(Object value) { return value == null ? null : String.valueOf(value); }
    private static String numberKey(Decimal value) { return value == null ? null : value.setScale(0).toPlainString(); }
    private static String numberKey(String value) { return value; }
    private static String truncate(String value, Integer limitValue) { return value == null || value.length() <= limitValue ? value : value.substring(0, limitValue); }
}
