public without sharing class SeasonTicketRelationshipService {
    private static final Integer LONG_TEXT_LIMIT = 32768;

    public class Stats {
        public Integer subjectsUpserted = 0;
        public Integer subjectsDeleted = 0;
        public Integer linesUpserted = 0;
        public Integer linesDeleted = 0;
        public Integer targetLookupsBackfilled = 0;
    }

    private class LineInput {
        private Id seasonTicketId;
        private Decimal ownerProductId;
        private String placementType;
        private String subjectCode;
        private Map<String, Object> payload;

        private LineInput(
            Id seasonTicketId,
            Decimal ownerProductId,
            String placementType,
            String subjectCode,
            Map<String, Object> payload
        ) {
            this.seasonTicketId = seasonTicketId;
            this.ownerProductId = ownerProductId;
            this.placementType = placementType;
            this.subjectCode = subjectCode;
            this.payload = payload;
        }
    }

    public static Stats sync(
        Map<Id, Map<String, Object>> payloadBySeasonTicketId,
        Map<Id, Decimal> ownerProductIdBySeasonTicketId
    ) {
        Stats stats = new Stats();
        if (payloadBySeasonTicketId == null || payloadBySeasonTicketId.isEmpty()) {
            return stats;
        }

        Map<Id, Map<String, Object>> scopedPayloads = new Map<Id, Map<String, Object>>();
        for (Id seasonTicketId : payloadBySeasonTicketId.keySet()) {
            Map<String, Object> payload = payloadBySeasonTicketId.get(seasonTicketId);
            if (
                payload != null &&
                (payload.containsKey('seasonTicketSubjects') || payload.containsKey('seasonTicketLines'))
            ) {
                scopedPayloads.put(seasonTicketId, payload);
            }
        }
        if (scopedPayloads.isEmpty()) {
            return stats;
        }

        Map<String, Season_Ticket_Subject__c> existingSubjectByKey = new Map<String, Season_Ticket_Subject__c>();
        for (Season_Ticket_Subject__c subject : [
            SELECT Id, Season_Ticket__c, Relationship_Key__c
            FROM Season_Ticket_Subject__c
            WHERE Season_Ticket__c IN :scopedPayloads.keySet()
        ]) {
            existingSubjectByKey.put(subject.Relationship_Key__c, subject);
        }

        List<Season_Ticket_Subject__c> subjects = new List<Season_Ticket_Subject__c>();
        Set<String> desiredSubjectKeys = new Set<String>();
        List<LineInput> lineInputs = new List<LineInput>();
        for (Id seasonTicketId : scopedPayloads.keySet()) {
            Map<String, Object> payload = scopedPayloads.get(seasonTicketId);
            Decimal ownerProductId = ownerProductIdBySeasonTicketId == null
                ? null
                : ownerProductIdBySeasonTicketId.get(seasonTicketId);
            if (ownerProductId == null) {
                continue;
            }

            List<Object> rawSubjects = asList(payload.get('seasonTicketSubjects'));
            if (rawSubjects != null) {
                for (Integer index = 0; index < rawSubjects.size(); index++) {
                    Map<String, Object> rawSubject = asMap(rawSubjects[index]);
                    if (rawSubject == null) {
                        continue;
                    }
                    String subjectCode = asString(rawSubject.get('code'));
                    if (String.isBlank(subjectCode)) {
                        subjectCode = 'subject-' + index;
                    }
                    String relationshipKey = subjectKey(ownerProductId, subjectCode);
                    desiredSubjectKeys.add(relationshipKey);
                    String nameIt = translation(rawSubject.get('externalName'), 'it');
                    String nameEn = translation(rawSubject.get('externalName'), 'en');
                    subjects.add(new Season_Ticket_Subject__c(
                        Relationship_Key__c = relationshipKey,
                        Season_Ticket__c = seasonTicketId,
                        Name = truncate(firstNotBlank(nameIt, nameEn, subjectCode), 80),
                        Subject_Code__c = truncate(subjectCode, 128),
                        Rank__c = asDecimal(rawSubject.get('rank')),
                        Min_Events__c = asDecimal(rawSubject.get('minEvents')),
                        Max_Events__c = asDecimal(rawSubject.get('maxEvents')),
                        Name_IT__c = truncate(nameIt, 255),
                        Name_EN__c = truncate(nameEn, 255),
                        Raw_JSON__c = shallowJson(rawSubject, new List<String>{
                            'code', 'rank', 'minEvents', 'maxEvents', 'externalName'
                        })
                    ));
                    addLines(
                        lineInputs,
                        seasonTicketId,
                        ownerProductId,
                        'subject',
                        subjectCode,
                        asList(rawSubject.get('seasonTicketLines'))
                    );
                }
            }
            addLines(
                lineInputs,
                seasonTicketId,
                ownerProductId,
                'root',
                '',
                asList(payload.get('seasonTicketLines'))
            );
        }

        if (!subjects.isEmpty()) {
            upsert subjects Relationship_Key__c;
            stats.subjectsUpserted = subjects.size();
        }
        Map<String, Id> subjectIdByKey = new Map<String, Id>();
        for (Season_Ticket_Subject__c subject : subjects) {
            subjectIdByKey.put(subject.Relationship_Key__c, subject.Id);
        }

        Set<Decimal> targetProductIds = new Set<Decimal>();
        for (LineInput input : lineInputs) {
            Decimal targetProductId = targetProductId(input.payload);
            if (targetProductId != null) {
                targetProductIds.add(targetProductId);
            }
        }
        Map<Decimal, Id> targetInventoryIdByProductId = new Map<Decimal, Id>();
        if (!targetProductIds.isEmpty()) {
            for (Inventory__c inventory : [
                SELECT Id, Inventory_Id__c
                FROM Inventory__c
                WHERE Inventory_Id__c IN :targetProductIds
            ]) {
                targetInventoryIdByProductId.put(inventory.Inventory_Id__c, inventory.Id);
            }
        }

        Map<String, Season_Ticket_Line__c> existingLineByKey = new Map<String, Season_Ticket_Line__c>();
        for (Season_Ticket_Line__c line : [
            SELECT Id, Season_Ticket__c, Relationship_Key__c
            FROM Season_Ticket_Line__c
            WHERE Season_Ticket__c IN :scopedPayloads.keySet()
        ]) {
            existingLineByKey.put(line.Relationship_Key__c, line);
        }

        List<Season_Ticket_Line__c> lines = new List<Season_Ticket_Line__c>();
        Set<String> desiredLineKeys = new Set<String>();
        for (LineInput input : lineInputs) {
            Decimal lineId = asDecimal(input.payload.get('seasonTicketLineId'));
            if (lineId == null) {
                continue;
            }
            String relationshipKey = lineKey(
                input.ownerProductId,
                lineId,
                input.placementType,
                input.subjectCode
            );
            desiredLineKeys.add(relationshipKey);
            Decimal targetProductId = targetProductId(input.payload);
            Map<String, Object> targetProduct = asMap(input.payload.get('product'));
            String targetCode = targetProduct == null ? null : asString(targetProduct.get('code'));
            lines.add(new Season_Ticket_Line__c(
                Relationship_Key__c = relationshipKey,
                Season_Ticket__c = input.seasonTicketId,
                Subject__c = String.isBlank(input.subjectCode)
                    ? null
                    : subjectIdByKey.get(subjectKey(input.ownerProductId, input.subjectCode)),
                Name = truncate(
                    numberKey(lineId) + (String.isBlank(targetCode) ? '' : ' - ' + targetCode),
                    80
                ),
                Season_Ticket_Line_Id__c = lineId,
                Placement_Type__c = input.placementType,
                Subject_Code__c = truncate(input.subjectCode, 128),
                Target_Product_Id__c = targetProductId,
                Target_Inventory__c = targetInventoryIdByProductId.get(targetProductId),
                Mandatory_Event__c = asBoolean(input.payload.get('mandatoryEvent')) == true,
                Multiple_Performances__c = truncate(asString(input.payload.get('multiplePerformances')), 32),
                Allow_Seat_Category_Change__c = asBoolean(input.payload.get('allowSeatCatUpDownGrade')) == true,
                Raw_JSON__c = shallowJson(input.payload, new List<String>{
                    'seasonTicketLineId', 'mandatoryEvent', 'multiplePerformances',
                    'allowSeatCatUpDownGrade'
                })
            ));
        }
        if (!lines.isEmpty()) {
            upsert lines Relationship_Key__c;
            stats.linesUpserted = lines.size();
        }

        List<Season_Ticket_Line__c> staleLines = new List<Season_Ticket_Line__c>();
        for (String existingKey : existingLineByKey.keySet()) {
            if (!desiredLineKeys.contains(existingKey)) {
                staleLines.add(existingLineByKey.get(existingKey));
            }
        }
        if (!staleLines.isEmpty()) {
            delete staleLines;
            stats.linesDeleted = staleLines.size();
        }

        List<Season_Ticket_Subject__c> staleSubjects = new List<Season_Ticket_Subject__c>();
        for (String existingKey : existingSubjectByKey.keySet()) {
            if (!desiredSubjectKeys.contains(existingKey)) {
                staleSubjects.add(existingSubjectByKey.get(existingKey));
            }
        }
        if (!staleSubjects.isEmpty()) {
            delete staleSubjects;
            stats.subjectsDeleted = staleSubjects.size();
        }
        return stats;
    }

    public static Integer backfillTargetInventories(List<Inventory__c> inventories) {
        Map<Decimal, Id> inventoryIdByProductId = new Map<Decimal, Id>();
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
        List<Season_Ticket_Line__c> updates = new List<Season_Ticket_Line__c>();
        for (Season_Ticket_Line__c line : [
            SELECT Id, Target_Product_Id__c
            FROM Season_Ticket_Line__c
            WHERE Target_Inventory__c = null
              AND Target_Product_Id__c IN :inventoryIdByProductId.keySet()
        ]) {
            Id targetInventoryId = inventoryIdByProductId.get(line.Target_Product_Id__c);
            if (targetInventoryId != null) {
                updates.add(new Season_Ticket_Line__c(
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

    private static void addLines(
        List<LineInput> output,
        Id seasonTicketId,
        Decimal ownerProductId,
        String placementType,
        String subjectCode,
        List<Object> rawLines
    ) {
        if (rawLines == null) {
            return;
        }
        for (Object rawLine : rawLines) {
            Map<String, Object> line = asMap(rawLine);
            if (line != null) {
                output.add(new LineInput(
                    seasonTicketId,
                    ownerProductId,
                    placementType,
                    subjectCode,
                    line
                ));
            }
        }
    }

    private static Decimal targetProductId(Map<String, Object> line) {
        Map<String, Object> product = line == null ? null : asMap(line.get('product'));
        return product == null ? null : asDecimal(product.get('id'));
    }

    private static String subjectKey(Decimal ownerProductId, String subjectCode) {
        return numberKey(ownerProductId) + '|subject|' + subjectCode;
    }

    private static String lineKey(
        Decimal ownerProductId,
        Decimal lineId,
        String placementType,
        String subjectCode
    ) {
        return numberKey(ownerProductId) + '|line|' + numberKey(lineId) + '|' +
            placementType + '|' + (subjectCode == null ? '' : subjectCode);
    }

    private static String translation(Object rawValue, String locale) {
        Map<String, Object> container = asMap(rawValue);
        List<Object> translations = container == null ? null : asList(container.get('translations'));
        if (translations == null) {
            return null;
        }
        for (Object rawTranslation : translations) {
            Map<String, Object> translationValue = asMap(rawTranslation);
            if (
                translationValue != null &&
                locale == asString(translationValue.get('locale'))
            ) {
                return asString(translationValue.get('value'));
            }
        }
        return null;
    }

    private static String shallowJson(Map<String, Object> source, List<String> keys) {
        Map<String, Object> shallow = new Map<String, Object>();
        for (String key : keys) {
            if (source.containsKey(key)) {
                shallow.put(key, source.get(key));
            }
        }
        Map<String, Object> product = asMap(source.get('product'));
        if (product != null) {
            shallow.put('targetProductId', product.get('id'));
            shallow.put('targetProductCode', product.get('code'));
        }
        return truncate(JSON.serialize(shallow), LONG_TEXT_LIMIT);
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
}
