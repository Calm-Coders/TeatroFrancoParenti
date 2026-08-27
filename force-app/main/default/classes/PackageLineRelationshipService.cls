public without sharing class PackageLineRelationshipService {
    private static final Integer LONG_TEXT_LIMIT = 32768;

    public class Stats {
        public Integer invalidPayloads = 0;
        public Integer linesUpserted = 0;
        public Integer linesDeleted = 0;
        public Integer audiencesUpserted = 0;
        public Integer parentLookupsLinked = 0;
        public Integer targetLookupsBackfilled = 0;
    }

    private class LineInput {
        private Id packId;
        private Integer sequence;
        private Map<String, Object> payload;
        private String relationshipKey;
    }

    private class AudienceResult {
        private Integer upserted = 0;
        private Map<String, Audience_Sub_Category__c> audienceByKey =
            new Map<String, Audience_Sub_Category__c>();
    }

    public static Stats syncInventoryPayloads(
        List<InventoryWrapper> products,
        List<Inventory__c> inventories,
        List<Pack__c> packs
    ) {
        Map<Id, Pack__c> packByInventoryId = new Map<Id, Pack__c>();
        if (packs != null) {
            for (Pack__c pack : packs) {
                if (pack.Id != null && pack.Inventory__c != null) {
                    packByInventoryId.put(pack.Inventory__c, pack);
                }
            }
        }

        Map<Id, Map<String, Object>> payloadByPackId = new Map<Id, Map<String, Object>>();
        Integer inputCount = products == null ? 0 : products.size();
        for (Integer index = 0; index < inputCount; index++) {
            if (inventories == null || index >= inventories.size()) {
                break;
            }
            Pack__c pack = packByInventoryId.get(inventories[index].Id);
            Map<String, Object> payload = asMap(products[index].pack);
            if (pack != null && payload != null) {
                payloadByPackId.put(pack.Id, payload);
            }
        }
        return sync(payloadByPackId);
    }

    public static Stats syncStoredPacks(List<Pack__c> packs) {
        Stats stats = new Stats();
        Map<Id, Map<String, Object>> payloadByPackId = new Map<Id, Map<String, Object>>();
        if (packs == null) {
            return stats;
        }
        for (Pack__c pack : packs) {
            if (pack.Id == null || String.isBlank(pack.Package_Lines__c)) {
                continue;
            }
            try {
                Object rawLines = JSON.deserializeUntyped(pack.Package_Lines__c);
                if (!(rawLines instanceof List<Object>)) {
                    stats.invalidPayloads++;
                    continue;
                }
                payloadByPackId.put(
                    pack.Id,
                    new Map<String, Object>{ 'packageLine' => rawLines }
                );
            } catch (Exception error) {
                stats.invalidPayloads++;
            }
        }
        mergeStats(stats, sync(payloadByPackId));
        return stats;
    }

    public static Stats sync(Map<Id, Map<String, Object>> payloadByPackId) {
        Stats stats = new Stats();
        if (payloadByPackId == null || payloadByPackId.isEmpty()) {
            return stats;
        }

        Map<Id, Map<String, Object>> scopedPayloads = new Map<Id, Map<String, Object>>();
        for (Id packId : payloadByPackId.keySet()) {
            Map<String, Object> payload = payloadByPackId.get(packId);
            if (payload != null && payload.containsKey('packageLine')) {
                scopedPayloads.put(packId, payload);
            }
        }
        if (scopedPayloads.isEmpty()) {
            return stats;
        }

        List<LineInput> inputs = new List<LineInput>();
        Set<String> targetProductIds = new Set<String>();
        Set<String> audienceKeys = new Set<String>();
        for (Id packId : scopedPayloads.keySet()) {
            List<Object> rawLines = asList(scopedPayloads.get(packId).get('packageLine'));
            if (rawLines == null) {
                continue;
            }
            for (Integer index = 0; index < rawLines.size(); index++) {
                Map<String, Object> payload = asMap(rawLines[index]);
                String lineId = payload == null ? null : idKey(payload.get('packageLineId'));
                if (payload == null || String.isBlank(lineId)) {
                    continue;
                }
                LineInput input = new LineInput();
                input.packId = packId;
                input.sequence = index + 1;
                input.payload = payload;
                input.relationshipKey = lineKey(packId, lineId);
                inputs.add(input);

                String targetProductId = targetProductId(payload);
                if (!String.isBlank(targetProductId)) {
                    targetProductIds.add(targetProductId);
                }
                String audienceKey = idKey(payload.get('forcedAudSubCatId'));
                if (!String.isBlank(audienceKey)) {
                    audienceKeys.add(audienceKey);
                }
            }
        }

        Map<String, Id> targetInventoryIdByProductId = new Map<String, Id>();
        if (!targetProductIds.isEmpty()) {
            for (Inventory__c inventory : [
                SELECT Id, Inventory_Id__c
                FROM Inventory__c
                WHERE Inventory_Id__c IN :targetProductIds
            ]) {
                targetInventoryIdByProductId.put(inventory.Inventory_Id__c, inventory.Id);
            }
        }
        AudienceResult audienceResult = ensureAudiences(audienceKeys);
        stats.audiencesUpserted = audienceResult.upserted;

        Map<String, Package_Line__c> existingLineByKey = new Map<String, Package_Line__c>();
        for (Package_Line__c line : [
            SELECT Id, Pack__c, Relationship_Key__c
            FROM Package_Line__c
            WHERE Pack__c IN :scopedPayloads.keySet()
        ]) {
            existingLineByKey.put(line.Relationship_Key__c, line);
        }

        List<Package_Line__c> lines = new List<Package_Line__c>();
        Map<String, LineInput> inputByKey = new Map<String, LineInput>();
        Set<String> desiredKeys = new Set<String>();
        for (LineInput input : inputs) {
            Map<String, Object> payload = input.payload;
            String lineId = idKey(payload.get('packageLineId'));
            String audienceId = idKey(payload.get('forcedAudSubCatId'));
            String audienceKey = audienceId;
            Audience_Sub_Category__c audience = audienceResult.audienceByKey.get(audienceKey);
            String targetId = targetProductId(payload);
            Map<String, Object> targetProduct = asMap(payload.get('product'));
            String targetCode = targetProduct == null ? null : asString(targetProduct.get('code'));
            desiredKeys.add(input.relationshipKey);
            inputByKey.put(input.relationshipKey, input);
            lines.add(new Package_Line__c(
                Relationship_Key__c = input.relationshipKey,
                Pack__c = input.packId,
                Name = truncate(
                    lineId + (String.isBlank(targetCode) ? '' : ' - ' + targetCode),
                    80
                ),
                Package_Line_Id__c = lineId,
                Sequence__c = input.sequence,
                Rank__c = asDecimal(payload.get('rank')),
                Quantity__c = asDecimal(payload.get('quantity')),
                Optional__c = asBoolean(payload.get('optional')) == true,
                Forced_Audience_Subcategory_Id__c = audienceId,
                Forced_Audience_Sub_Category__c = audience == null ? null : audience.Id,
                Target_Product_Id__c = targetId,
                Target_Product_Code__c = truncate(targetCode, 128),
                Target_Inventory__c = targetInventoryIdByProductId.get(targetId),
                Parent_Package_Line_Id__c = idKey(payload.get('parentPackageLineId')),
                Raw_JSON__c = shallowJson(payload)
            ));
        }
        if (!lines.isEmpty()) {
            upsert lines Relationship_Key__c;
            stats.linesUpserted = lines.size();
        }

        Map<String, Id> lineIdByKey = new Map<String, Id>();
        for (Package_Line__c line : lines) {
            lineIdByKey.put(line.Relationship_Key__c, line.Id);
        }
        List<Package_Line__c> parentUpdates = new List<Package_Line__c>();
        for (Package_Line__c line : lines) {
            LineInput input = inputByKey.get(line.Relationship_Key__c);
            String parentLineId = idKey(input.payload.get('parentPackageLineId'));
            Id parentId = String.isBlank(parentLineId)
                ? null
                : lineIdByKey.get(lineKey(input.packId, parentLineId));
            if (parentId == line.Id) {
                parentId = null;
            }
            parentUpdates.add(new Package_Line__c(
                Id = line.Id,
                Parent_Package_Line__c = parentId
            ));
            if (parentId != null) {
                stats.parentLookupsLinked++;
            }
        }
        if (!parentUpdates.isEmpty()) {
            update parentUpdates;
        }

        List<Package_Line__c> staleLines = new List<Package_Line__c>();
        for (String existingKey : existingLineByKey.keySet()) {
            if (!desiredKeys.contains(existingKey)) {
                staleLines.add(existingLineByKey.get(existingKey));
            }
        }
        if (!staleLines.isEmpty()) {
            delete staleLines;
            stats.linesDeleted = staleLines.size();
        }
        return stats;
    }

    public static Integer backfillTargetInventories(List<Inventory__c> inventories) {
        Map<String, Id> inventoryIdByProductId = new Map<String, Id>();
        if (inventories != null) {
            for (Inventory__c inventory : inventories) {
                if (inventory.Id != null && inventory.Inventory_Id__c != null) {
                    inventoryIdByProductId.put(inventory.Inventory_Id__c, inventory.Id);
                }
            }
        }
        if (inventoryIdByProductId.isEmpty()) {
            return 0;
        }
        List<Package_Line__c> updates = new List<Package_Line__c>();
        for (Package_Line__c line : [
            SELECT Id, Target_Product_Id__c
            FROM Package_Line__c
            WHERE Target_Inventory__c = null
              AND Target_Product_Id__c IN :inventoryIdByProductId.keySet()
        ]) {
            Id targetInventoryId = inventoryIdByProductId.get(line.Target_Product_Id__c);
            if (targetInventoryId != null) {
                updates.add(new Package_Line__c(
                    Id = line.Id,
                    Target_Inventory__c = targetInventoryId
                ));
            }
        }
        if (!updates.isEmpty()) {
            update updates;
        }
        return updates.size();
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

    private static String targetProductId(Map<String, Object> line) {
        Map<String, Object> product = line == null ? null : asMap(line.get('product'));
        return product == null ? null : idKey(product.get('id'));
    }

    private static String shallowJson(Map<String, Object> payload) {
        Map<String, Object> shallow = new Map<String, Object>();
        for (String key : new List<String>{
            'packageLineId', 'quantity', 'optional', 'forcedAudSubCatId',
            'rank', 'parentPackageLineId'
        }) {
            if (payload.containsKey(key)) {
                shallow.put(key, payload.get(key));
            }
        }
        Map<String, Object> product = asMap(payload.get('product'));
        if (product != null) {
            shallow.put('targetProductId', product.get('id'));
            shallow.put('targetProductCode', product.get('code'));
        }
        return truncate(JSON.serialize(shallow), LONG_TEXT_LIMIT);
    }

    private static String lineKey(Id packId, String lineId) {
        return String.valueOf(packId) + '|line|' + lineId;
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
        if (value == null || String.isBlank(String.valueOf(value))) {
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

    private static Boolean asBoolean(Object value) {
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return value == null ? null : 'true'.equalsIgnoreCase(String.valueOf(value));
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

    private static void mergeStats(Stats target, Stats source) {
        target.invalidPayloads += source.invalidPayloads;
        target.linesUpserted += source.linesUpserted;
        target.linesDeleted += source.linesDeleted;
        target.audiencesUpserted += source.audiencesUpserted;
        target.parentLookupsLinked += source.parentLookupsLinked;
        target.targetLookupsBackfilled += source.targetLookupsBackfilled;
    }
}
