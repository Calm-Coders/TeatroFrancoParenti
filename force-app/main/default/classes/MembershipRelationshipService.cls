public without sharing class MembershipRelationshipService {
    private static final Integer LONG_TEXT_LIMIT = 32768;

    public class Stats {
        public Integer invalidPayloads = 0;
        public Integer audiencesUpserted = 0;
        public Integer itemsUpserted = 0;
        public Integer itemsDeleted = 0;
        public Integer pricesUpserted = 0;
        public Integer pricesDeleted = 0;
        public Integer salePeriodsUpserted = 0;
        public Integer salePeriodsDeleted = 0;
        public Integer salePeriodAudiencesUpdated = 0;
    }

    private class PriceInput {
        private String itemKey;
        private Id itemId;
        private Integer sequence;
        private String priceKey;
        private String audienceKey;
        private String audienceId;
        private Map<String, Object> payload;
    }

    private class AudienceResult {
        private Integer upserted = 0;
        private Map<String, Audience_Sub_Category__c> audienceByKey =
            new Map<String, Audience_Sub_Category__c>();
    }

    public static Stats syncInventoryPayloads(
        List<InventoryWrapper> products,
        List<Inventory__c> inventories,
        List<Membership__c> memberships
    ) {
        Map<Id, Membership__c> membershipByInventoryId = new Map<Id, Membership__c>();
        for (Membership__c membership : memberships) {
            if (membership.Id != null && membership.Inventory__c != null) {
                membershipByInventoryId.put(membership.Inventory__c, membership);
            }
        }

        Map<Id, Map<String, Object>> payloadByMembershipId = new Map<Id, Map<String, Object>>();
        for (Integer index = 0; index < products.size(); index++) {
            Membership__c membership = membershipByInventoryId.get(inventories[index].Id);
            Map<String, Object> payload = asMap(products[index].membership);
            if (membership != null && payload != null) {
                payloadByMembershipId.put(membership.Id, payload);
            }
        }
        return sync(payloadByMembershipId);
    }

    public static Stats syncStoredMemberships(List<Membership__c> memberships) {
        Stats stats = new Stats();
        Map<Id, Map<String, Object>> payloadByMembershipId = new Map<Id, Map<String, Object>>();
        for (Membership__c membership : memberships) {
            if (membership.Id == null || String.isBlank(membership.Items__c)) {
                continue;
            }
            try {
                Object rawItems = JSON.deserializeUntyped(membership.Items__c);
                if (!(rawItems instanceof List<Object>)) {
                    stats.invalidPayloads++;
                    continue;
                }
                payloadByMembershipId.put(
                    membership.Id,
                    new Map<String, Object>{ 'items' => rawItems }
                );
            } catch (Exception error) {
                stats.invalidPayloads++;
            }
        }
        mergeStats(stats, sync(payloadByMembershipId));
        return stats;
    }

    public static Stats sync(Map<Id, Map<String, Object>> payloadByMembershipId) {
        Stats stats = new Stats();
        if (payloadByMembershipId == null || payloadByMembershipId.isEmpty()) {
            return stats;
        }

        Map<Id, Map<String, Object>> scopedPayloads = new Map<Id, Map<String, Object>>();
        for (Id membershipId : payloadByMembershipId.keySet()) {
            Map<String, Object> payload = payloadByMembershipId.get(membershipId);
            if (payload != null && payload.containsKey('items')) {
                scopedPayloads.put(membershipId, payload);
            }
        }
        if (scopedPayloads.isEmpty()) {
            return stats;
        }

        Map<String, Membership_Item__c> existingItemByKey = new Map<String, Membership_Item__c>();
        Set<Id> existingItemIds = new Set<Id>();
        for (Membership_Item__c item : [
            SELECT Id, Membership__c, Relationship_Key__c
            FROM Membership_Item__c
            WHERE Membership__c IN :scopedPayloads.keySet()
        ]) {
            existingItemByKey.put(item.Relationship_Key__c, item);
            existingItemIds.add(item.Id);
        }

        Map<String, Membership_Item_Price__c> existingPriceByKey =
            new Map<String, Membership_Item_Price__c>();
        if (!existingItemIds.isEmpty()) {
            for (Membership_Item_Price__c price : [
                SELECT Id, Membership_Item__c, Price_Key__c
                FROM Membership_Item_Price__c
                WHERE Membership_Item__c IN :existingItemIds
            ]) {
                existingPriceByKey.put(price.Price_Key__c, price);
            }
        }

        List<Membership_Item__c> items = new List<Membership_Item__c>();
        Set<String> desiredItemKeys = new Set<String>();
        Map<String, List<Map<String, Object>>> pricePayloadsByItemKey =
            new Map<String, List<Map<String, Object>>>();
        for (Id membershipId : scopedPayloads.keySet()) {
            List<Object> rawItems = asList(scopedPayloads.get(membershipId).get('items'));
            if (rawItems == null) {
                continue;
            }
            for (Integer itemIndex = 0; itemIndex < rawItems.size(); itemIndex++) {
                Map<String, Object> payload = asMap(rawItems[itemIndex]);
                String externalId = payload == null ? null : idKey(payload.get('itemId'));
                if (payload == null || String.isBlank(externalId)) {
                    continue;
                }
                String relationshipKey = itemKey(membershipId, externalId);
                desiredItemKeys.add(relationshipKey);
                String nameIt = translation(payload.get('externalName'), 'it');
                String nameEn = translation(payload.get('externalName'), 'en');
                String code = asString(payload.get('code'));
                String displayName = firstNotBlank(
                    nameIt,
                    nameEn,
                    String.isBlank(code) ? 'Membership Item ' + externalId : code
                );
                items.add(new Membership_Item__c(
                    Relationship_Key__c = relationshipKey,
                    Membership__c = membershipId,
                    Name = truncate(displayName, 80),
                    Item_Id__c = externalId,
                    Sequence__c = itemIndex,
                    Code__c = truncate(code, 80),
                    Kind__c = truncate(asString(payload.get('kind')), 80),
                    Item_Class__c = truncate(asString(payload.get('itemClass')), 80),
                    Rank__c = asDecimal(payload.get('rank')),
                    Transport_Trip_Type__c = truncate(
                        asString(payload.get('transportTripType')),
                        80
                    ),
                    Donation_Amount__c = money(payload.get('donationAmount')),
                    Donation_Min_Amount__c = money(payload.get('donationMinAmount')),
                    Donation_Max_Amount__c = money(payload.get('donationMaxAmount')),
                    Voucher_Amount__c = money(payload.get('voucherAmount')),
                    Voucher_Min_Amount__c = money(payload.get('voucherMinAmount')),
                    Voucher_Max_Amount__c = money(payload.get('voucherMaxAmount')),
                    Name_IT__c = truncate(nameIt, 255),
                    Name_EN__c = truncate(nameEn, 255),
                    Raw_JSON__c = shallowJson(payload, 'itemPrices')
                ));

                List<Map<String, Object>> pricePayloads = new List<Map<String, Object>>();
                List<Object> rawPrices = asList(payload.get('itemPrices'));
                if (rawPrices != null) {
                    for (Object rawPrice : rawPrices) {
                        Map<String, Object> pricePayload = asMap(rawPrice);
                        if (pricePayload != null) {
                            pricePayloads.add(pricePayload);
                        }
                    }
                }
                pricePayloadsByItemKey.put(relationshipKey, pricePayloads);
            }
        }

        if (!items.isEmpty()) {
            upsert items Relationship_Key__c;
            stats.itemsUpserted = items.size();
        }
        Map<String, Membership_Item__c> desiredItemByKey = new Map<String, Membership_Item__c>();
        for (Membership_Item__c item : items) {
            desiredItemByKey.put(item.Relationship_Key__c, item);
        }

        List<PriceInput> priceInputs = new List<PriceInput>();
        Set<String> desiredPriceKeys = new Set<String>();
        Set<String> audienceKeys = new Set<String>();
        Map<String, Integer> occurrenceByBaseKey = new Map<String, Integer>();
        for (String relationshipKey : pricePayloadsByItemKey.keySet()) {
            Membership_Item__c parentItem = desiredItemByKey.get(relationshipKey);
            if (parentItem == null) {
                continue;
            }
            List<Map<String, Object>> pricePayloads = pricePayloadsByItemKey.get(relationshipKey);
            for (Integer priceIndex = 0; priceIndex < pricePayloads.size(); priceIndex++) {
                Map<String, Object> payload = pricePayloads[priceIndex];
                String audienceId = idKey(payload.get('audSubCatId'));
                String audienceKey = audienceId;
                String baseKey = relationshipKey + '|price|' +
                    (String.isBlank(audienceKey) ? 'NONE' : audienceKey);
                Integer occurrence = occurrenceByBaseKey.containsKey(baseKey)
                    ? occurrenceByBaseKey.get(baseKey)
                    : 0;
                occurrenceByBaseKey.put(baseKey, occurrence + 1);

                PriceInput input = new PriceInput();
                input.itemKey = relationshipKey;
                input.itemId = parentItem.Id;
                input.sequence = priceIndex;
                input.priceKey = occurrence == 0
                    ? baseKey
                    : baseKey + '|DUP:' + String.valueOf(occurrence);
                input.audienceKey = audienceKey;
                input.audienceId = audienceId;
                input.payload = payload;
                priceInputs.add(input);
                desiredPriceKeys.add(input.priceKey);
                if (!String.isBlank(audienceKey)) {
                    audienceKeys.add(audienceKey);
                }
            }
        }

        AudienceResult audienceResult = ensureAudiences(audienceKeys);
        Map<String, Audience_Sub_Category__c> audienceByKey = audienceResult.audienceByKey;
        stats.audiencesUpserted = audienceResult.upserted;

        List<Membership_Item_Price__c> prices = new List<Membership_Item_Price__c>();
        Map<String, PriceInput> inputByPriceKey = new Map<String, PriceInput>();
        for (PriceInput input : priceInputs) {
            Audience_Sub_Category__c audience = audienceByKey.get(input.audienceKey);
            prices.add(new Membership_Item_Price__c(
                Price_Key__c = input.priceKey,
                Membership_Item__c = input.itemId,
                Audience_Sub_Category__c = audience == null ? null : audience.Id,
                Audience_Subcategory_Id__c = input.audienceId,
                Amount__c = money(input.payload.get('amount')),
                Min_Quantity__c = asDecimal(input.payload.get('minQty')),
                Max_Quantity__c = asDecimal(input.payload.get('maxQty')),
                Sequence__c = input.sequence,
                Raw_JSON__c = shallowJson(input.payload, 'salePeriods')
            ));
            inputByPriceKey.put(input.priceKey, input);
        }
        if (!prices.isEmpty()) {
            upsert prices Price_Key__c;
            stats.pricesUpserted = prices.size();
        }

        Map<Id, Object> salePeriodsByPriceId = new Map<Id, Object>();
        Set<Id> desiredPriceIds = new Set<Id>();
        for (Membership_Item_Price__c price : prices) {
            desiredPriceIds.add(price.Id);
            salePeriodsByPriceId.put(
                price.Id,
                inputByPriceKey.get(price.Price_Key__c).payload.get('salePeriods')
            );
        }
        SalePeriodRelationshipService.Stats periodStats =
            SalePeriodRelationshipService.syncMembershipItemPrices(salePeriodsByPriceId);
        stats.salePeriodsUpserted = periodStats.salePeriodsUpserted;
        stats.salePeriodsDeleted = periodStats.salePeriodsDeleted;

        if (!desiredPriceIds.isEmpty()) {
            List<Sale_Period_Audience__c> restrictions = [
                SELECT Id, Audience_Sub_Category__c, Audience_Subcategory_Id__c,
                       Code__c, Name_IT__c, Kind__c
                FROM Sale_Period_Audience__c
                WHERE Sale_Period__r.Membership_Item_Price__c IN :desiredPriceIds
            ];
            PerformancePriceRelationshipService.Stats audienceStats =
                PerformancePriceRelationshipService.syncStoredSalePeriodAudiences(restrictions);
            stats.salePeriodAudiencesUpdated = audienceStats.audiencesUpserted;
        }

        List<Membership_Item_Price__c> stalePrices = new List<Membership_Item_Price__c>();
        Set<Id> stalePriceIds = new Set<Id>();
        for (String existingKey : existingPriceByKey.keySet()) {
            if (!desiredPriceKeys.contains(existingKey)) {
                Membership_Item_Price__c stalePrice = existingPriceByKey.get(existingKey);
                stalePrices.add(stalePrice);
                stalePriceIds.add(stalePrice.Id);
            }
        }
        if (!stalePriceIds.isEmpty()) {
            SalePeriodRelationshipService.deleteForMembershipItemPrices(stalePriceIds);
            delete stalePrices;
            stats.pricesDeleted = stalePrices.size();
        }

        List<Membership_Item__c> staleItems = new List<Membership_Item__c>();
        for (String existingKey : existingItemByKey.keySet()) {
            if (!desiredItemKeys.contains(existingKey)) {
                staleItems.add(existingItemByKey.get(existingKey));
            }
        }
        if (!staleItems.isEmpty()) {
            delete staleItems;
            stats.itemsDeleted = staleItems.size();
        }
        return stats;
    }

    public static void deleteSalePeriodsForMemberships(List<Membership__c> memberships) {
        Set<Id> membershipIds = new Set<Id>();
        for (Membership__c membership : memberships) {
            if (membership.Id != null) {
                membershipIds.add(membership.Id);
            }
        }
        if (membershipIds.isEmpty()) {
            return;
        }
        Set<Id> priceIds = new Set<Id>();
        for (Membership_Item_Price__c price : [
            SELECT Id
            FROM Membership_Item_Price__c
            WHERE Membership_Item__r.Membership__c IN :membershipIds
        ]) {
            priceIds.add(price.Id);
        }
        SalePeriodRelationshipService.deleteForMembershipItemPrices(priceIds);
    }

    private static AudienceResult ensureAudiences(Set<String> audienceKeys) {
        AudienceResult result = new AudienceResult();
        if (audienceKeys.isEmpty()) {
            return result;
        }
        for (Audience_Sub_Category__c audience : [
            SELECT Id, Audience_Key__c
            FROM Audience_Sub_Category__c
            WHERE Audience_Key__c IN :audienceKeys
        ]) {
            result.audienceByKey.put(audience.Audience_Key__c, audience);
        }
        List<Audience_Sub_Category__c> missing = new List<Audience_Sub_Category__c>();
        for (String key : audienceKeys) {
            if (!result.audienceByKey.containsKey(key)) {
                missing.add(new Audience_Sub_Category__c(
                    Name = truncate('Audience ' + key, 80),
                    Audience_Key__c = key,
                    Audience_Subcategory_Id__c = key
                ));
            }
        }
        if (!missing.isEmpty()) {
            upsert missing Audience_Key__c;
            result.upserted = missing.size();
            for (Audience_Sub_Category__c audience : missing) {
                result.audienceByKey.put(audience.Audience_Key__c, audience);
            }
        }
        return result;
    }

    private static void mergeStats(Stats target, Stats source) {
        target.invalidPayloads += source.invalidPayloads;
        target.audiencesUpserted += source.audiencesUpserted;
        target.itemsUpserted += source.itemsUpserted;
        target.itemsDeleted += source.itemsDeleted;
        target.pricesUpserted += source.pricesUpserted;
        target.pricesDeleted += source.pricesDeleted;
        target.salePeriodsUpserted += source.salePeriodsUpserted;
        target.salePeriodsDeleted += source.salePeriodsDeleted;
        target.salePeriodAudiencesUpdated += source.salePeriodAudiencesUpdated;
    }

    private static String itemKey(Id membershipId, String externalId) {
        return String.valueOf(membershipId) + '|item|' + externalId;
    }

    private static String translation(Object rawValue, String locale) {
        Map<String, Object> container = asMap(rawValue);
        List<Object> translations = container == null ? null : asList(container.get('translations'));
        String fallback;
        if (translations == null) {
            return null;
        }
        for (Object rawTranslation : translations) {
            Map<String, Object> translationValue = asMap(rawTranslation);
            String value = translationValue == null ? null : asString(translationValue.get('value'));
            if (String.isBlank(value)) {
                continue;
            }
            if (locale == asString(translationValue.get('locale'))) {
                return value;
            }
            if (fallback == null) {
                fallback = value;
            }
        }
        return fallback;
    }

    private static String shallowJson(Map<String, Object> source, String excludedKey) {
        Map<String, Object> shallow = new Map<String, Object>();
        for (String key : source.keySet()) {
            if (key != excludedKey) {
                shallow.put(key, source.get(key));
            }
        }
        return truncate(JSON.serialize(shallow), LONG_TEXT_LIMIT);
    }

    private static Decimal money(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof String) {
            String original = String.valueOf(value).trim();
            String cleaned = original.replaceAll('[^0-9,.-]', '');
            if (String.isBlank(cleaned)) {
                return null;
            }
            if (cleaned.contains(',') && cleaned.contains('.')) {
                cleaned = cleaned.replace('.', '').replace(',', '.');
            } else {
                cleaned = cleaned.replace(',', '.');
            }
            try {
                Decimal parsed = Decimal.valueOf(cleaned);
                return original.contains('.') || original.contains(',') ? parsed : parsed / 100;
            } catch (Exception error) {
                return null;
            }
        }
        Decimal parsed = asDecimal(value);
        return parsed == null ? null : parsed / 100;
    }

    private static String firstNotBlank(String first, String second, String fallbackValue) {
        if (!String.isBlank(first)) {
            return first;
        }
        return String.isBlank(second) ? fallbackValue : second;
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

    private static String idKey(Object value) {
        Decimal numeric = asDecimal(value);
        return numeric == null ? asString(value) : numeric.setScale(0).toPlainString();
    }

    private static String numberKey(Decimal value) {
        return value == null ? '' : String.valueOf(value.setScale(0));
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }
}
