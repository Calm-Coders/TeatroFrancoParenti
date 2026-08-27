public without sharing class CrossSellProductRelationshipService {
    private static final Integer LONG_TEXT_LIMIT = 32768;

    public class Stats {
        public Integer linksUpserted = 0;
        public Integer targetsLinked = 0;
        public Integer linksDeleted = 0;
    }

    private class Input {
        public Id sourceInventoryId;
        public String sourceProductId;
        public Integer sequence;
        public Map<String, Object> payload;
    }

    public static Stats syncInventoryPayloads(
        List<InventoryWrapper> products,
        List<Inventory__c> inventories
    ) {
        List<Input> inputs = new List<Input>();
        Set<Id> scopedInventoryIds = new Set<Id>();
        for (Integer productIndex = 0; productIndex < products.size(); productIndex++) {
            InventoryWrapper product = products[productIndex];
            Inventory__c inventory = inventories[productIndex];
            List<Object> links = asList(product.crossSellProductLinks);
            if (inventory.Id == null || links == null) continue;
            scopedInventoryIds.add(inventory.Id);
            addInputs(
                inputs,
                inventory.Id,
                idKey(product.id),
                links
            );
        }
        return sync(inputs, scopedInventoryIds);
    }

    public static Stats syncEnrichment(Map<Id, Map<String, Object>> productsByInventoryId) {
        List<Input> inputs = new List<Input>();
        Set<Id> scopedInventoryIds = new Set<Id>();
        Map<Id, String> productIdByInventoryId = new Map<Id, String>();
        for (Inventory__c inventory : [
            SELECT Id, Inventory_Id__c
            FROM Inventory__c
            WHERE Id IN :productsByInventoryId.keySet()
        ]) {
            productIdByInventoryId.put(inventory.Id, inventory.Inventory_Id__c);
        }
        for (Id inventoryId : productsByInventoryId.keySet()) {
            Map<String, Object> product = productsByInventoryId.get(inventoryId);
            if (!product.containsKey('crossSellProductLinks')) continue;
            List<Object> links = asList(product.get('crossSellProductLinks'));
            if (links == null) continue;
            scopedInventoryIds.add(inventoryId);
            addInputs(inputs, inventoryId, productIdByInventoryId.get(inventoryId), links);
        }
        return sync(inputs, scopedInventoryIds);
    }

    public static Integer backfillTargetInventories(List<Inventory__c> inventories) {
        Map<String, Id> inventoryIdByProductId = new Map<String, Id>();
        for (Inventory__c inventory : inventories) {
            if (inventory.Id != null && inventory.Inventory_Id__c != null) {
                inventoryIdByProductId.put(inventory.Inventory_Id__c, inventory.Id);
            }
        }
        if (inventoryIdByProductId.isEmpty()) return 0;

        List<Cross_Sell_Product_Link__c> updates = new List<Cross_Sell_Product_Link__c>();
        for (Cross_Sell_Product_Link__c link : [
            SELECT Id, Target_Product_Id__c
            FROM Cross_Sell_Product_Link__c
            WHERE Target_Inventory__c = null
              AND Target_Product_Id__c IN :inventoryIdByProductId.keySet()
        ]) {
            Id targetInventoryId = inventoryIdByProductId.get(link.Target_Product_Id__c);
            if (targetInventoryId != null) {
                updates.add(new Cross_Sell_Product_Link__c(
                    Id = link.Id,
                    Target_Inventory__c = targetInventoryId
                ));
            }
        }
        if (!updates.isEmpty()) update updates;
        return updates.size();
    }

    private static void addInputs(
        List<Input> inputs,
        Id sourceInventoryId,
        String sourceProductId,
        List<Object> rawLinks
    ) {
        for (Integer sequence = 0; sequence < rawLinks.size(); sequence++) {
            Map<String, Object> payload = asMap(rawLinks[sequence]);
            if (payload == null) continue;
            Input input = new Input();
            input.sourceInventoryId = sourceInventoryId;
            input.sourceProductId = sourceProductId;
            input.sequence = sequence;
            input.payload = payload;
            inputs.add(input);
        }
    }

    private static Stats sync(List<Input> inputs, Set<Id> scopedInventoryIds) {
        Stats stats = new Stats();
        if (scopedInventoryIds.isEmpty()) return stats;

        Set<String> targetProductIds = new Set<String>();
        for (Input input : inputs) {
            String targetProductId = targetProductId(input.payload);
            if (targetProductId != null) targetProductIds.add(targetProductId);
        }
        Map<String, Inventory__c> targetByProductId = new Map<String, Inventory__c>();
        if (!targetProductIds.isEmpty()) {
            for (Inventory__c target : [
                SELECT Id, Inventory_Id__c, Name
                FROM Inventory__c
                WHERE Inventory_Id__c IN :targetProductIds
            ]) targetByProductId.put(target.Inventory_Id__c, target);
        }

        Set<String> desiredKeys = new Set<String>();
        List<Cross_Sell_Product_Link__c> links = new List<Cross_Sell_Product_Link__c>();
        for (Input input : inputs) {
            String linkId = idKey(input.payload.get('id'));
            String targetProductId = targetProductId(input.payload);
            String key = relationshipKey(
                input.sourceProductId,
                input.sourceInventoryId,
                linkId,
                targetProductId,
                input.sequence
            );
            desiredKeys.add(key);
            Inventory__c target = targetByProductId.get(targetProductId);
            Map<String, Object> targetPayload = asMap(input.payload.get('targetProduct'));
            String targetName = firstString(
                targetPayload == null ? null : targetPayload.get('name_it'),
                targetPayload == null ? null : targetPayload.get('name'),
                target == null ? null : target.Name
            );
            String linkType = firstString(input.payload.get('type'), input.payload.get('linkType'));
            String messageIt = message(input.payload, 'it');
            String messageEn = message(input.payload, 'en');
            String displayName = firstString(targetName, linkType, 'Cross Sell Link');
            links.add(new Cross_Sell_Product_Link__c(
                Name = truncate(displayName, 80),
                Relationship_Key__c = key,
                Source_Inventory__c = input.sourceInventoryId,
                Source_Product_Id__c = input.sourceProductId,
                Cross_Sell_Link_Id__c = linkId,
                Target_Inventory__c = target == null ? null : target.Id,
                Target_Product_Id__c = targetProductId,
                Target_Product_Name__c = truncate(targetName, 255),
                Link_Type__c = truncate(linkType, 80),
                Message_IT__c = truncate(messageIt, LONG_TEXT_LIMIT),
                Message_EN__c = truncate(messageEn, LONG_TEXT_LIMIT),
                Start__c = asDatetime(firstObject(input.payload.get('start'), input.payload.get('validFrom'))),
                End__c = asDatetime(firstObject(input.payload.get('end'), input.payload.get('validTo'))),
                Base_Min_Quantity__c = asDecimal(input.payload.get('baseMinQuantity')),
                Target_Product_Rank__c = asDecimal(input.payload.get('targetProductRank')),
                Target_Quantity_Type__c = truncate(asString(input.payload.get('targetQuantityType')), 80),
                Target_Same_Date_As_Base__c = asBoolean(input.payload.get('targetSameDateAsBase')) == true,
                Sequence__c = input.sequence,
                Raw_JSON__c = truncate(JSON.serialize(input.payload), LONG_TEXT_LIMIT)
            ));
            if (target != null) stats.targetsLinked++;
        }
        if (!links.isEmpty()) upsert links Relationship_Key__c;
        stats.linksUpserted = links.size();

        List<Cross_Sell_Product_Link__c> staleLinks = new List<Cross_Sell_Product_Link__c>();
        for (Cross_Sell_Product_Link__c existing : [
            SELECT Id, Relationship_Key__c
            FROM Cross_Sell_Product_Link__c
            WHERE Source_Inventory__c IN :scopedInventoryIds
        ]) {
            if (!desiredKeys.contains(existing.Relationship_Key__c)) staleLinks.add(existing);
        }
        if (!staleLinks.isEmpty()) delete staleLinks;
        stats.linksDeleted = staleLinks.size();
        return stats;
    }

    private static String targetProductId(Map<String, Object> payload) {
        String value = idKey(payload.get('targetProductId'));
        Map<String, Object> target = asMap(payload.get('targetProduct'));
        return String.isBlank(value) && target != null ? idKey(target.get('id')) : value;
    }

    private static String relationshipKey(
        String sourceProductId,
        Id sourceInventoryId,
        String linkId,
        String targetProductId,
        Integer sequence
    ) {
        String sourceKey = String.isBlank(sourceProductId) ? String.valueOf(sourceInventoryId) : sourceProductId;
        String linkKey = String.isBlank(linkId) ? 'ROW:' + sequence : 'LINK:' + linkId;
        String targetKey = String.isBlank(targetProductId) ? 'ROW:' + sequence : 'TARGET:' + targetProductId;
        return sourceKey + '|' + linkKey + '|' + targetKey;
    }

    private static String message(Map<String, Object> payload, String locale) {
        String localized = asString(payload.get('message_' + locale));
        if (!String.isBlank(localized)) return localized;
        String generic = asString(payload.get('message'));
        if (!String.isBlank(generic)) return generic;
        return translatedValue(payload.get('description'), locale);
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

    private static Datetime asDatetime(Object value) {
        if (value == null) return null;
        try {
            return validSalesforceDatetime((Datetime) JSON.deserialize(JSON.serialize(value), Datetime.class));
        } catch (Exception ignored) {
            String text = asString(value);
            try { return validSalesforceDatetime(Datetime.valueOf(text.substring(0, 19).replace('T', ' '))); }
            catch (Exception alsoIgnored) { return null; }
        }
    }

    private static Datetime validSalesforceDatetime(Datetime value) {
        return value != null && value.year() >= 1700 && value.year() <= 4000 ? value : null;
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
    private static Map<String, Object> asMap(Object value) { return value instanceof Map<String, Object> ? (Map<String, Object>) value : null; }
    private static List<Object> asList(Object value) { return value instanceof List<Object> ? (List<Object>) value : null; }
    private static Decimal asDecimal(Object value) { if (value == null) return null; try { return Decimal.valueOf(String.valueOf(value)); } catch (Exception ignored) { return null; } }
    private static Boolean asBoolean(Object value) { return value instanceof Boolean ? (Boolean) value : value == null ? null : String.valueOf(value).toLowerCase() == 'true'; }
    private static String asString(Object value) { return value == null ? null : String.valueOf(value); }
    private static String idKey(Object value) { Decimal numeric = asDecimal(value); return numeric == null ? asString(value) : numeric.setScale(0).toPlainString(); }
    private static String numberKey(Decimal value) { return value == null ? null : value.setScale(0).toPlainString(); }
    private static String truncate(String value, Integer limitValue) { return value == null || value.length() <= limitValue ? value : value.substring(0, limitValue); }
}
