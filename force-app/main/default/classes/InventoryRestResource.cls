@RestResource(urlMapping='/v1/inventories')
global without sharing class InventoryRestResource {
    private static final Integer MAX_LOG_LENGTH = 131072;
    private static final Integer MAX_LONG_TEXT_LENGTH = 32768;
    private static final String FLOW_NAME = 'InventoryRestResource.receiveInventory';

    @HttpPost
    global static void receiveInventory() {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }

        Integration_Log__c logRec = new Integration_Log__c();
        initializeLog(logRec, FLOW_NAME);

        try {
            String rawBody = (RestContext.request == null || RestContext.request.requestBody == null) ? null : RestContext.request.requestBody.toString();
            logRec.Request_Body__c = trimForLog(rawBody);

            if (String.isBlank(rawBody)) {
                setResponse(400, new Map<String, Object>{ 'success' => false, 'message' => 'Request body is required.' }, logRec, true);
                return;
            }

            List<InventoryWrapper> products;
            try {
                products = deserializePayloads(rawBody);
            } catch (System.JSONException e) {
                populateException(logRec, e);
                setResponse(400, new Map<String, Object>{ 'success' => false, 'message' => 'Invalid JSON payload.' }, logRec, true);
                return;
            }

            if (products.isEmpty()) {
                setResponse(400, new Map<String, Object>{ 'success' => false, 'message' => 'At least one inventory payload is required.' }, logRec, true);
                return;
            }

            List<String> productIds = new List<String>();
            List<String> productCodes = new List<String>();
            List<String> productStates = new List<String>();
            List<Inventory__c> recordsToInsert = new List<Inventory__c>();

            for (InventoryWrapper inventoryWrapper : products) {
                validatePayload(inventoryWrapper);
                recordsToInsert.add(buildInventoryRecord(inventoryWrapper));

                if (inventoryWrapper.id != null) {
                    productIds.add(String.valueOf(inventoryWrapper.id));
                }

                if (!String.isBlank(inventoryWrapper.code)) {
                    productCodes.add(inventoryWrapper.code);
                }

                if (!String.isBlank(inventoryWrapper.state)) {
                    productStates.add(inventoryWrapper.state);
                }
            }

            insert recordsToInsert;

            List<String> recordIds = new List<String>();
            for (Inventory__c recordItem : recordsToInsert) {
                recordIds.add(recordItem.Id);
            }

            setResponse(200, new Map<String, Object>{
                'success' => true,
                'processedProducts' => products.size(),
                'recordIds' => recordIds,
                'productIds' => productIds,
                'productCodes' => productCodes,
                'productStates' => productStates,
                'message' => 'Inventory webhook accepted.'
            }, logRec, false);
        } catch (InventoryWebhookException e) {
            populateException(logRec, e);
            setResponse(400, new Map<String, Object>{ 'success' => false, 'message' => e.getMessage() }, logRec, true);
        } catch (DmlException e) {
            populateException(logRec, e);
            setResponse(400, new Map<String, Object>{ 'success' => false, 'message' => e.getDmlMessage(0) }, logRec, true);
        } catch (Exception e) {
            populateException(logRec, e);
            setResponse(500, new Map<String, Object>{ 'success' => false, 'message' => e.getMessage() }, logRec, true);
        } finally {
            insert logRec;
        }
    }

    private static List<InventoryWrapper> deserializePayloads(String rawBody) {
        String trimmedBody = rawBody == null ? null : rawBody.trim();

        if (String.isBlank(trimmedBody)) {
            return new List<InventoryWrapper>();
        }

        Object rawPayload = JSON.deserializeUntyped(trimmedBody);
        List<InventoryWrapper> payloads = new List<InventoryWrapper>();

        if (rawPayload instanceof List<Object>) {
            for (Object item : (List<Object>) rawPayload) {
                payloads.add(buildWrapper(item));
            }
            return payloads;
        }

        payloads.add(buildWrapper(rawPayload));
        return payloads;
    }

    private static InventoryWrapper buildWrapper(Object rawPayload) {
        if (!(rawPayload instanceof Map<String, Object>)) {
            throw new InventoryWebhookException('Each inventory payload must be a valid JSON object.');
        }

        return buildInventoryWrapper((Map<String, Object>) rawPayload);
    }

    private static InventoryWrapper buildInventoryWrapper(Map<String, Object> rawPayload) {
        InventoryWrapper inventoryWrapper = new InventoryWrapper();
        inventoryWrapper.id = asLong(rawPayload.get('id'));
        inventoryWrapper.prevSeasonProductId = asLong(rawPayload.get('prevSeasonProductId'));
        inventoryWrapper.code = asString(rawPayload.get('code'));
        inventoryWrapper.productFamilyType = asString(rawPayload.get('productFamilyType'));
        inventoryWrapper.productFamilySubType = asString(rawPayload.get('productFamilySubType'));
        inventoryWrapper.audienceType = asString(rawPayload.get('audienceType'));
        inventoryWrapper.state = asString(rawPayload.get('state'));
        inventoryWrapper.logo = asString(rawPayload.get('logo'));
        inventoryWrapper.smallImageUrl = asString(rawPayload.get('smallImageUrl'));
        inventoryWrapper.mediumImageUrl = asString(rawPayload.get('mediumImageUrl'));
        inventoryWrapper.largeImageUrl = asString(rawPayload.get('largeImageUrl'));
        inventoryWrapper.detailURL = asString(rawPayload.get('detailURL'));
        inventoryWrapper.vatCodeId = asLong(rawPayload.get('vatCodeId'));
        inventoryWrapper.ticketModelId = asLong(rawPayload.get('ticketModelId'));
        inventoryWrapper.chargesTableId = asLong(rawPayload.get('chargesTableId'));
        inventoryWrapper.partnerContactNumber = asString(rawPayload.get('partnerContactNumber'));
        inventoryWrapper.productTypeId = asLong(rawPayload.get('productTypeId'));
        inventoryWrapper.allowQuestionnaire = asBoolean(rawPayload.get('allowQuestionnaire'));
        inventoryWrapper.questionnaireId = asLong(rawPayload.get('questionnaireId'));
        inventoryWrapper.salePeriods = rawPayload.get('salePeriods');
        inventoryWrapper.saleCloseExceptions = rawPayload.get('saleCloseExceptions');
        inventoryWrapper.externalName = rawPayload.get('externalName');
        inventoryWrapper.internalName = rawPayload.get('internalName');
        inventoryWrapper.shortName = rawPayload.get('shortName');
        inventoryWrapper.externalDescription = rawPayload.get('externalDescription');
        inventoryWrapper.optionAvailabilities = rawPayload.get('optionAvailabilities');
        inventoryWrapper.crossSellProductLinks = rawPayload.get('crossSellProductLinks');
        inventoryWrapper.subTopicLinks = rawPayload.get('subTopicLinks');
        inventoryWrapper.productSocialNetworkLinks = rawPayload.get('productSocialNetworkLinks');
        inventoryWrapper.comfortVariableValues = rawPayload.get('comfortVariableValues');
        inventoryWrapper.media = rawPayload.get('media');
        inventoryWrapper.event = rawPayload.get('event');
        inventoryWrapper.service = rawPayload.get('service');
        inventoryWrapper.goods = rawPayload.get('goods');
        inventoryWrapper.pack = rawPayload.get('pack');
        inventoryWrapper.seasonTicket = rawPayload.get('seasonTicket');
        inventoryWrapper.transport = rawPayload.get('transport');
        inventoryWrapper.pass = rawPayload.get('pass');
        inventoryWrapper.membership = rawPayload.get('membership');
        inventoryWrapper.hospitality = rawPayload.get('hospitality');
        inventoryWrapper.minQuantity = asDecimal(rawPayload.get('minQuantity'));
        inventoryWrapper.maxQuantity = asDecimal(rawPayload.get('maxQuantity'));
        inventoryWrapper.culturalContact = rawPayload.get('culturalContact');
        inventoryWrapper.waitingListAllowed = asBoolean(rawPayload.get('waitingListAllowed'));
        inventoryWrapper.partnerContactId = asLong(rawPayload.get('partnerContactId'));
        return inventoryWrapper;
    }

    private static void validatePayload(InventoryWrapper inventoryWrapper) {
        if (inventoryWrapper == null) {
            throw new InventoryWebhookException('Each inventory payload must be a valid JSON object.');
        }
    }

    private static Inventory__c buildInventoryRecord(InventoryWrapper inventoryWrapper) {
        Inventory__c recordItem = new Inventory__c(
            Name = buildRecordName(inventoryWrapper)
        );

        setCustomField(recordItem, 'Inventory_Id__c', inventoryWrapper.id);
        setCustomField(recordItem, 'Prev_Season_Product_Id__c', inventoryWrapper.prevSeasonProductId);
        setCustomField(recordItem, 'Code__c', truncateValue(inventoryWrapper.code, 255));
        setCustomField(recordItem, 'Product_Family_Type__c', truncateValue(inventoryWrapper.productFamilyType, 80));
        setCustomField(recordItem, 'Product_Family_Sub_Type__c', truncateValue(inventoryWrapper.productFamilySubType, 80));
        setCustomField(recordItem, 'Audience_Type__c', truncateValue(inventoryWrapper.audienceType, 80));
        setCustomField(recordItem, 'State__c', truncateValue(inventoryWrapper.state, 80));
        setCustomField(recordItem, 'Logo__c', truncateValue(inventoryWrapper.logo, 255));
        setCustomField(recordItem, 'Small_Image_Url__c', truncateValue(inventoryWrapper.smallImageUrl, 255));
        setCustomField(recordItem, 'Medium_Image_Url__c', truncateValue(inventoryWrapper.mediumImageUrl, 255));
        setCustomField(recordItem, 'Large_Image_Url__c', truncateValue(inventoryWrapper.largeImageUrl, 255));
        setCustomField(recordItem, 'Detail_URL__c', truncateValue(inventoryWrapper.detailURL, 255));
        setCustomField(recordItem, 'Vat_Code_Id__c', inventoryWrapper.vatCodeId);
        setCustomField(recordItem, 'Ticket_Model_Id__c', inventoryWrapper.ticketModelId);
        setCustomField(recordItem, 'Charges_Table_Id__c', inventoryWrapper.chargesTableId);
        setCustomField(recordItem, 'Partner_Contact_Number__c', truncateValue(inventoryWrapper.partnerContactNumber, 80));
        setCustomField(recordItem, 'Product_Type_Id__c', inventoryWrapper.productTypeId);
        setCustomField(recordItem, 'Allow_Questionnaire__c', inventoryWrapper.allowQuestionnaire);
        setCustomField(recordItem, 'Questionnaire_Id__c', inventoryWrapper.questionnaireId);
        setCustomField(recordItem, 'Sale_Periods__c', serializeRawValue(inventoryWrapper.salePeriods, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Sale_Close_Exceptions__c', serializeRawValue(inventoryWrapper.saleCloseExceptions, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'External_Name__c', serializeRawValue(inventoryWrapper.externalName, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Internal_Name__c', serializeRawValue(inventoryWrapper.internalName, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Short_Name__c', serializeRawValue(inventoryWrapper.shortName, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'External_Description__c', serializeRawValue(inventoryWrapper.externalDescription, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Option_Availabilities__c', serializeRawValue(inventoryWrapper.optionAvailabilities, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Cross_Sell_Product_Links__c', serializeRawValue(inventoryWrapper.crossSellProductLinks, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Sub_Topic_Links__c', serializeRawValue(inventoryWrapper.subTopicLinks, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Product_Social_Network_Links__c', serializeRawValue(inventoryWrapper.productSocialNetworkLinks, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Comfort_Variable_Values__c', serializeRawValue(inventoryWrapper.comfortVariableValues, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Media__c', serializeRawValue(inventoryWrapper.media, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Event__c', serializeRawValue(inventoryWrapper.event, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Service__c', serializeRawValue(inventoryWrapper.service, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Goods__c', serializeRawValue(inventoryWrapper.goods, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Pack__c', serializeRawValue(inventoryWrapper.pack, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Season_Ticket__c', serializeRawValue(inventoryWrapper.seasonTicket, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Transport__c', serializeRawValue(inventoryWrapper.transport, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Pass__c', serializeRawValue(inventoryWrapper.pass, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Membership__c', serializeRawValue(inventoryWrapper.membership, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Hospitality__c', serializeRawValue(inventoryWrapper.hospitality, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Min_Quantity__c', inventoryWrapper.minQuantity);
        setCustomField(recordItem, 'Max_Quantity__c', inventoryWrapper.maxQuantity);
        setCustomField(recordItem, 'Cultural_Contact__c', serializeRawValue(inventoryWrapper.culturalContact, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Waiting_List_Allowed__c', inventoryWrapper.waitingListAllowed);
        setCustomField(recordItem, 'Partner_Contact_Id__c', inventoryWrapper.partnerContactId);

        return recordItem;
    }

    private static String buildRecordName(InventoryWrapper inventoryWrapper) {
        if (!String.isBlank(inventoryWrapper.code)) {
            return inventoryWrapper.code.left(80);
        }

        if (inventoryWrapper.id != null) {
            return ('Inventory ' + String.valueOf(inventoryWrapper.id)).left(80);
        }

        return 'Inventory';
    }

    private static void setCustomField(SObject recordItem, String fieldApiName, Object value) {
        if (recordItem == null || String.isBlank(fieldApiName) || value == null) {
            return;
        }

        Map<String, SObjectField> fieldMap = recordItem.getSObjectType().getDescribe().fields.getMap();
        if (fieldMap.containsKey(fieldApiName)) {
            DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();
            Object coercedValue = coerceFieldValue(fieldDescribe, value);
            if (coercedValue != null) {
                recordItem.put(fieldApiName, coercedValue);
            }
        }
    }

    private static Object coerceFieldValue(DescribeFieldResult fieldDescribe, Object value) {
        if (fieldDescribe == null || value == null) {
            return null;
        }

        DisplayType fieldType = fieldDescribe.getType();
        String stringValue = String.valueOf(value);

        if (
            fieldType == DisplayType.String ||
            fieldType == DisplayType.TextArea ||
            fieldType == DisplayType.EncryptedString ||
            fieldType == DisplayType.Phone ||
            fieldType == DisplayType.Url ||
            fieldType == DisplayType.Email ||
            fieldType == DisplayType.Picklist ||
            fieldType == DisplayType.MultiPicklist ||
            fieldType == DisplayType.Reference ||
            fieldType == DisplayType.Id
        ) {
            return truncateValue(stringValue, fieldDescribe.getLength());
        }

        if (
            fieldType == DisplayType.Integer ||
            fieldType == DisplayType.Double ||
            fieldType == DisplayType.Currency ||
            fieldType == DisplayType.Percent
        ) {
            try {
                return Decimal.valueOf(stringValue);
            } catch (Exception e) {
                return null;
            }
        }

        if (fieldType == DisplayType.Boolean) {
            if (value instanceof Boolean) {
                return value;
            }

            if (stringValue == 'true') {
                return true;
            }

            if (stringValue == 'false') {
                return false;
            }

            return null;
        }

        if (fieldType == DisplayType.Date) {
            if (String.isBlank(stringValue) || stringValue.length() < 10) {
                return null;
            }

            try {
                return Date.valueOf(stringValue.substring(0, 10));
            } catch (Exception e) {
                return null;
            }
        }

        if (fieldType == DisplayType.DateTime) {
            if (String.isBlank(stringValue) || stringValue.length() < 19) {
                return null;
            }

            try {
                return Datetime.valueOf(stringValue.substring(0, 19).replace('T', ' '));
            } catch (Exception e) {
                return null;
            }
        }

        return value;
    }

    private static String serializeRawValue(Object value, Integer maxLength) {
        if (value == null) {
            return null;
        }

        return truncateValue(JSON.serialize(value), maxLength);
    }

    private static String truncateValue(String value, Integer maxLength) {
        if (value == null || maxLength == null || value.length() <= maxLength) {
            return value;
        }

        return value.substring(0, maxLength);
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Long asLong(Object value) {
        if (value == null) {
            return null;
        }

        try {
            return Long.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal asDecimal(Object value) {
        if (value == null) {
            return null;
        }

        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static Boolean asBoolean(Object value) {
        if (value == null) {
            return null;
        }

        if (value instanceof Boolean) {
            return (Boolean) value;
        }

        String stringValue = String.valueOf(value);
        if (stringValue == 'true') {
            return true;
        }

        if (stringValue == 'false') {
            return false;
        }

        return null;
    }

    private static void setResponse(Integer statusCode, Map<String, Object> payload, Integration_Log__c logRec, Boolean isError) {
        String responseJson = JSON.serialize(payload);
        RestContext.response.statusCode = statusCode;
        RestContext.response.responseBody = Blob.valueOf(responseJson);

        logRec.Is_Error__c = isError;
        logRec.Response_State__c = String.valueOf(statusCode);
        logRec.Response_Body__c = trimForLog(responseJson);
    }

    private static void populateException(Integration_Log__c logRec, Exception e) {
        logRec.Exception_Message__c = trimForLog(e.getMessage());
        logRec.Exception_StackTrace__c = trimForLog(e.getStackTraceString());
    }

    private static String trimForLog(String value) {
        if (value == null) {
            return null;
        }

        return value.abbreviate(MAX_LOG_LENGTH);
    }

    private static void initializeLog(Integration_Log__c logRec, String flowName) {
        RestRequest req = RestContext.request;

        logRec.Flow_Name__c = flowName;
        logRec.Integration_Type__c = 'Inbound';
        logRec.Is_Error__c = false;
        logRec.Request_Endpoint__c = (req == null) ? null : req.resourcePath;

        if (req != null && req.headers != null) {
            logRec.Request_Headers__c = JSON.serialize(req.headers);
        }
    }

    global class InventoryWebhookException extends Exception {
    }
}
