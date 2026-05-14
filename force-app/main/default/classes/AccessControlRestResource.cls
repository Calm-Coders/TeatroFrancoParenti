@RestResource(urlMapping='/v1/accesscontrol')
global without sharing class AccessControlRestResource {
    private static final Integer MAX_LOG_LENGTH = 131072;
    private static final Integer MAX_LONG_TEXT_LENGTH = 32768;
    private static final String FLOW_NAME = 'AccessControlRestResource.receiveAccessControl';

    @HttpPost
    global static void receiveAccessControl() {
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

            List<AccessControlWrapper> tickets;
            try {
                tickets = deserializePayloads(rawBody);
            } catch (System.JSONException e) {
                populateException(logRec, e);
                setResponse(400, new Map<String, Object>{ 'success' => false, 'message' => 'Invalid JSON payload.' }, logRec, true);
                return;
            }

            if (tickets.isEmpty()) {
                setResponse(400, new Map<String, Object>{ 'success' => false, 'message' => 'At least one access payload is required.' }, logRec, true);
                return;
            }

            List<Access_Control__c> recordsToInsert = new List<Access_Control__c>();
            List<String> barcodes = new List<String>();
            List<String> ticketIds = new List<String>();
            List<String> orderIds = new List<String>();

            for (AccessControlWrapper accessControlWrapper : tickets) {
                validatePayload(accessControlWrapper);
                recordsToInsert.add(buildAccessControlRecord(accessControlWrapper));

                if (!String.isBlank(accessControlWrapper.barcode)) {
                    barcodes.add(accessControlWrapper.barcode);
                }

                if (accessControlWrapper.ticketId != null) {
                    ticketIds.add(String.valueOf(accessControlWrapper.ticketId));
                }

                if (accessControlWrapper.orderId != null) {
                    orderIds.add(String.valueOf(accessControlWrapper.orderId));
                }
            }

            insert recordsToInsert;

            List<String> recordIds = new List<String>();
            for (Access_Control__c recordItem : recordsToInsert) {
                recordIds.add(recordItem.Id);
            }

            setResponse(200, new Map<String, Object>{
                'success' => true,
                'processedTickets' => tickets.size(),
                'recordIds' => recordIds,
                'barcodes' => barcodes,
                'ticketIds' => ticketIds,
                'orderIds' => orderIds,
                'message' => 'Access control webhook accepted.'
            }, logRec, false);
        } catch (AccessControlWebhookException e) {
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

    private static List<AccessControlWrapper> deserializePayloads(String rawBody) {
        String trimmedBody = rawBody == null ? null : rawBody.trim();

        if (String.isBlank(trimmedBody)) {
            return new List<AccessControlWrapper>();
        }

        Object rawPayload = JSON.deserializeUntyped(trimmedBody);
        List<AccessControlWrapper> payloads = new List<AccessControlWrapper>();

        if (rawPayload instanceof List<Object>) {
            for (Object item : (List<Object>) rawPayload) {
                payloads.add(buildWrapper(item));
            }
            return payloads;
        }

        payloads.add(buildWrapper(rawPayload));
        return payloads;
    }

    private static AccessControlWrapper buildWrapper(Object rawPayload) {
        if (!(rawPayload instanceof Map<String, Object>)) {
            throw new AccessControlWebhookException('Each access payload must be a valid JSON object.');
        }

        return (AccessControlWrapper) JSON.deserialize(
            JSON.serialize(rawPayload),
            AccessControlWrapper.class
        );
    }

    private static void validatePayload(AccessControlWrapper accessControlWrapper) {
        if (accessControlWrapper == null) {
            throw new AccessControlWebhookException('Each access payload must be a valid JSON object.');
        }
    }

    private static Access_Control__c buildAccessControlRecord(AccessControlWrapper accessControlWrapper) {
        Access_Control__c recordItem = new Access_Control__c(
            Name = buildRecordName(accessControlWrapper)
        );

        setCustomField(recordItem, 'Barcode__c', truncateValue(accessControlWrapper.barcode, 255));
        setCustomField(recordItem, 'Ticket_Id__c', accessControlWrapper.ticketId);
        setCustomField(recordItem, 'Ticket_State__c', truncateValue(accessControlWrapper.ticketState, 40));
        setCustomField(recordItem, 'Cancellation_Cause__c', truncateValue(accessControlWrapper.cancellationCause, 80));
        setCustomField(recordItem, 'Tariff_Code__c', truncateValue(accessControlWrapper.tariffCode, 80));
        setCustomField(recordItem, 'Product_Id__c', accessControlWrapper.productId);
        setCustomField(recordItem, 'Product_Code__c', truncateValue(accessControlWrapper.productCode, 80));
        setCustomField(recordItem, 'Validity_Start_Time__c', truncateValue(accessControlWrapper.validityStartTime, 40));
        setCustomField(recordItem, 'Cultural_Contact_Number__c', truncateValue(accessControlWrapper.culturalContactNumber, 80));
        setCustomField(recordItem, 'Holder_Info__c', serializeRawValue(accessControlWrapper.holderInfo, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Validity_End_Time__c', truncateValue(accessControlWrapper.validityEndTime, 40));
        setCustomField(recordItem, 'Sales_Channel_Code_Mapping__c', truncateValue(accessControlWrapper.salesChannelCodeMapping, 40));
        setCustomField(recordItem, 'Order_Id__c', accessControlWrapper.orderId);
        setCustomField(recordItem, 'Creation_Date__c', truncateValue(accessControlWrapper.creationDate, 40));
        setCustomField(recordItem, 'Group_Size__c', accessControlWrapper.groupSize);
        setCustomField(recordItem, 'Price__c', accessControlWrapper.price);

        return recordItem;
    }

    private static String buildRecordName(AccessControlWrapper accessControlWrapper) {
        if (!String.isBlank(accessControlWrapper.barcode)) {
            return accessControlWrapper.barcode.left(80);
        }

        if (accessControlWrapper.ticketId != null) {
            return ('Ticket ' + String.valueOf(accessControlWrapper.ticketId)).left(80);
        }

        if (accessControlWrapper.orderId != null) {
            return ('Order ' + String.valueOf(accessControlWrapper.orderId)).left(80);
        }

        return 'Access Control';
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

    global class AccessControlWebhookException extends Exception {
    }
}
