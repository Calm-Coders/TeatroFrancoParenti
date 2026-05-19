@RestResource(urlMapping='/v1/orders')
global without sharing class OrderRestResource {
    private static final Integer MAX_LOG_LENGTH = 131072;
    private static final Integer MAX_SECUTIX_LONG_TEXT_LENGTH = 32768;
    private static final String FLOW_NAME = 'OrderRestResource.receiveOrder';
    private static final String DEFAULT_ORDER_STATUS = 'Draft';

    @HttpPost
    global static void receiveOrder() {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }

        Integration_Log__c logRec = new Integration_Log__c();
        initializeLog(logRec, FLOW_NAME);

        try {
            String rawBody = (RestContext.request == null || RestContext.request.requestBody == null) ? null: RestContext.request.requestBody.toString();
            logRec.Request_Body__c = trimForLog(rawBody);

            if (String.isBlank(rawBody)) {
                setResponse(400,new Map<String, Object>{'success' => false,'message' => 'Request body is required.'},logRec,true);
                return;
            }

            List<OrderWrapper> orders;
            try {
                orders = deserializePayloads(rawBody);
            } catch (System.JSONException e) {
                populateException(logRec, e);
                setResponse(400, new Map<String, Object>{'success' => false,'message' => 'Invalid JSON payload.'},logRec,true);
                return;
            }

            if (orders.isEmpty()) {
                setResponse(400,new Map<String, Object>{'success' => false,'message' => 'At least one order payload is required.'}, logRec, true);
                return;
            }

            Savepoint sp = Database.setSavepoint();
            List<String> orderIds = new List<String>();
            List<String> orderSecretIds = new List<String>();
            List<String> contactReferences = new List<String>();
            List<String> recordIds = new List<String>();

            try {
                for (OrderWrapper orderWrapper : orders) {
                    validatePayload(orderWrapper);

                    Order newOrder = createOrder(orderWrapper);
                    recordIds.add(newOrder.Id);

                    OrderWrapper.OrderDetailsData details = orderWrapper.payload.orderDetailsData;
                    if (details.orderId != null) {
                        orderIds.add(String.valueOf(details.orderId));
                    }

                    if (!String.isBlank(details.orderSecretId)) {
                        orderSecretIds.add(details.orderSecretId);
                    }

                    String contactReference = firstContactReference(details);
                    if (!String.isBlank(contactReference)) {
                        contactReferences.add(contactReference);
                    }
                }
            } catch (Exception e) {
                Database.rollback(sp);
                throw e;
            }

            setResponse(200,new Map<String, Object>{
                'success' => true,
                'processedOrders' => orders.size(),
                'recordIds' => recordIds,
                'orderIds' => orderIds,
                'orderSecretIds' => orderSecretIds,
                'contactReferences' => contactReferences,
                'message' => 'Order webhook accepted.'
            },logRec,false );
        } catch (OrderWebhookException e) {
            populateException(logRec, e);
            setResponse(400, new Map<String, Object>{ 'success' => false,'message' => e.getMessage() },logRec,true);
        } catch (DmlException e) {
            populateException(logRec, e);
            setResponse(400, new Map<String, Object>{ 'success' => false,'message' => e.getDmlMessage(0) },logRec,true);
        } catch (Exception e) {
            populateException(logRec, e);
            setResponse(500, new Map<String, Object>{ 'success' => false,'message' => e.getMessage() },logRec,true);
        } finally {
            insert logRec;
        }
    }

    private static List<OrderWrapper> deserializePayloads(String rawBody) {
        String trimmedBody = rawBody == null ? null : rawBody.trim();

        if (String.isBlank(trimmedBody)) {
            return new List<OrderWrapper>();
        }

        Object rawPayload = JSON.deserializeUntyped(trimmedBody);
        List<OrderWrapper> payloads = new List<OrderWrapper>();

        if (rawPayload instanceof List<Object>) {
            for (Object item : (List<Object>) rawPayload) {
                payloads.add(buildPayloadEnvelope(item));
            }
            return payloads;
        }

        payloads.add(buildPayloadEnvelope(rawPayload));
        return payloads;
    }

    private static OrderWrapper buildPayloadEnvelope(Object rawPayload) {
        if (!(rawPayload instanceof Map<String, Object>)) {
            throw new OrderWebhookException('Each order payload must be a valid JSON object.');
        }

        Map<String, Object> rawPayloadMap = (Map<String, Object>) rawPayload;
        OrderWrapper orderWrapper = new OrderWrapper();
        orderWrapper.rawPayload = rawPayloadMap;
        orderWrapper.payload = (OrderWrapper.Payload) JSON.deserialize(
            JSON.serialize(rawPayloadMap),
            OrderWrapper.Payload.class
        );
        return orderWrapper;
    }

    private static void validatePayload(OrderWrapper orderWrapper) {
        if (orderWrapper == null || orderWrapper.payload == null) {
            throw new OrderWebhookException('Each order payload must be a valid JSON object.');
        }

        if (orderWrapper.payload.orderDetailsData == null) {
            throw new OrderWebhookException('The orderDetailsData node is required.');
        }
    }

    private static Order createOrder(OrderWrapper orderWrapper) {
        OrderWrapper.OrderDetailsData details = orderWrapper.payload.orderDetailsData;
        Order orderRecord = buildOrder(orderWrapper);
        insert orderRecord;
        return orderRecord;
    }

    private static Order buildOrder(OrderWrapper orderWrapper) {
        OrderWrapper.OrderDetailsData details = orderWrapper.payload.orderDetailsData;
        String contactReference = firstContactReference(details);
        Id accountId = createFallbackAccount(details, contactReference).Id;

        Order orderRecord = new Order();
        orderRecord.AccountId = accountId;
        orderRecord.EffectiveDate = resolveEffectiveDate(details);
        orderRecord.Status = DEFAULT_ORDER_STATUS;
        orderRecord.Description = buildDescription(orderWrapper);
        setCustomField(orderRecord, 'Order_Id__c', truncateValue(details.orderId == null ? null : String.valueOf(details.orderId), 30));
        setCustomField(orderRecord, 'Order_Secret_Id__c', truncateValue(details.orderSecretId, 255));
        setCustomField(orderRecord, 'Order_State__c', truncateValue(details.orderState, 40));
        setCustomField(orderRecord, 'Order_Type__c', truncateValue(details.orderType, 40));
        setCustomField(orderRecord, 'Contact_Reference__c', truncateValue(contactReference, 80));
        setCustomField(orderRecord, 'Order_Detail_Granularity__c', truncateValue(orderWrapper.payload.orderDetailGranularity, 40));
        setCustomField(orderRecord, 'Creation_Date_Time__c', truncateValue(details.creationDateTime, 40));
        setCustomField(orderRecord, 'Reference_Date__c', truncateValue(details.referenceDate, 40));
        setCustomField(orderRecord, 'Expiration_Date__c', truncateValue(details.expirationDate, 40));
        setCustomField(orderRecord, 'Order_Originator__c', truncateValue(details.orderOriginator, 80));
        setCustomField(orderRecord, 'Sales_Channel_Code__c', truncateValue(details.salesChannelCode, 40));
        setCustomField(orderRecord, 'Sales_Channel_Type__c', truncateValue(details.salesChannelType, 80));
        setCustomField(orderRecord, 'Organization_Code__c', truncateValue(details.organizationCode, 80));
        setCustomField(orderRecord, 'Multicurrency__c', details.multicurrency);
        setCustomField(orderRecord, 'Sale_Amount__c', details.saleAmount);
        setCustomField(orderRecord, 'Pre_Sale_Amount__c', details.preSaleAmount);
        setCustomField(orderRecord, 'Reservation_Amount__c', details.reservationAmount);
        setCustomField(orderRecord, 'Option_Amount__c', details.optionAmount);
        setCustomField(orderRecord, 'Waiting_Account_Balance_Amount__c', details.waitingAccountBalanceAmount);
        setCustomField(orderRecord, 'Operation_Datas__c', serializeRawValue(details.operationDatas, MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Movement_Datas__c', serializeRawValue(details.movementDatas, MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Movement_Ticket_Datas__c', serializeRawValue(details.movementTicketDatas, MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Sales_Channel_Name__c', serializeRawValue(details.salesChannelName, MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Generated_Contiguities__c', serializeRawValue(details.generatedContiguities, MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Order_Origin_Data__c', serializeRawValue(details.orderOriginData, MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Order_Installments__c', serializeRawValue(details.orderInstallmentsToCreate, MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Catalog_Currency__c', serializeRawValue(details.catalogCurrency, MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Organization_Name__c', serializeRawValue(details.organizationName, MAX_SECUTIX_LONG_TEXT_LENGTH));

        return orderRecord;
    }

    private static Account createFallbackAccount(OrderWrapper.OrderDetailsData details, String contactReference) {
        Account fallbackAccount = new Account(
            Name = buildFallbackAccountName(details, contactReference)
        );
        insert fallbackAccount;
        return fallbackAccount;
    }

    private static String buildFallbackAccountName(OrderWrapper.OrderDetailsData details, String contactReference) {
        List<String> parts = new List<String>();
        if (!String.isBlank(contactReference)) {
            parts.add('Contact ' + contactReference);
        }
        if (details != null && details.orderId != null) {
            parts.add('Order ' + String.valueOf(details.orderId));
        }

        String baseName = parts.isEmpty() ? 'Secutix Order' : String.join(parts, ' ');
        return ('Secutix - ' + baseName).left(255);
    }

    private static String firstContactReference(OrderWrapper.OrderDetailsData details) {
        if (details == null) {
            return null;
        }

        if (!String.isBlank(details.contactReference)) {
            return details.contactReference;
        }

        if (details.movementDatas != null) {
            for (OrderWrapper.MovementData movement : details.movementDatas) {
                if (movement != null && !String.isBlank(movement.contactReference)) {
                    return movement.contactReference;
                }
            }
        }

        return null;
    }

    private static Date resolveEffectiveDate(OrderWrapper.OrderDetailsData details) {
        Date effectiveDate = parseDate(details == null ? null : details.referenceDate);
        if (effectiveDate != null) {
            return effectiveDate;
        }

        effectiveDate = parseDate(details == null ? null : details.creationDateTime);
        if (effectiveDate != null) {
            return effectiveDate;
        }

        if (details != null && details.operationDatas != null) {
            for (OrderWrapper.OperationData operation : details.operationDatas) {
                effectiveDate = parseDate(operation == null ? null : operation.itemDate);
                if (effectiveDate != null) {
                    return effectiveDate;
                }
            }
        }

        return Date.today();
    }

    private static Date parseDate(String rawValue) {
        if (String.isBlank(rawValue) || rawValue.length() < 10) {
            return null;
        }

        try {
            return Date.valueOf(rawValue.substring(0, 10));
        } catch (Exception e) {
            return null;
        }
    }

    private static String buildDescription(OrderWrapper orderWrapper) {
        OrderWrapper.OrderDetailsData details = orderWrapper == null || orderWrapper.payload == null ? null : orderWrapper.payload.orderDetailsData;
        if (details == null) {
            return null;
        }

        List<String> lines = new List<String>();
        addLabelValue(lines, 'Secutix orderId', details.orderId == null ? null : String.valueOf(details.orderId));
        addLabelValue(lines, 'Secutix orderSecretId', details.orderSecretId);
        addLabelValue(lines, 'Secutix orderState', details.orderState);
        addLabelValue(lines, 'Secutix orderType', details.orderType);
        addLabelValue(lines, 'Secutix contactReference', firstContactReference(details));
        addLabelValue(lines, 'Secutix orderDetailGranularity', orderWrapper.payload.orderDetailGranularity);
        addLabelValue(lines, 'Secutix creationDateTime', details.creationDateTime);
        addLabelValue(lines, 'Secutix referenceDate', details.referenceDate);
        addLabelValue(lines, 'Secutix expirationDate', details.expirationDate);
        addLabelValue(lines, 'Secutix saleAmount', details.saleAmount == null ? null : String.valueOf(details.saleAmount));
        addLabelValue(lines, 'Secutix preSaleAmount', details.preSaleAmount == null ? null : String.valueOf(details.preSaleAmount));
        addLabelValue(lines, 'Secutix salesChannelCode', details.salesChannelCode);
        addLabelValue(lines, 'Secutix orderOriginator', details.orderOriginator);

        if (details.operationDatas != null && !details.operationDatas.isEmpty()) {
            OrderWrapper.OperationData firstOperation = details.operationDatas[0];
            addLabelValue(lines, 'First operation product', firstOperation == null ? null : firstOperation.product);
            addLabelValue(lines, 'First operation site', firstOperation == null ? null : firstOperation.site);
            addLabelValue(lines, 'First operation itemDate', firstOperation == null ? null : firstOperation.itemDate);
        }

        return lines.isEmpty() ? null : String.join(lines, '\n');
    }

    private static void addLabelValue(List<String> values, String label, String value) {
        if (!String.isBlank(value)) {
            values.add(label + ': ' + value);
        }
    }

    private static void setCustomField(SObject recordItem, String fieldApiName, Object value) {
        if (recordItem == null || String.isBlank(fieldApiName) || value == null) {
            return;
        }

        Map<String, SObjectField> fieldMap = recordItem.getSObjectType().getDescribe().fields.getMap();
        if (fieldMap.containsKey(fieldApiName)) {
            recordItem.put(fieldApiName, value);
        }
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

    private static void setResponse( Integer statusCode, Map<String, Object> payload,Integration_Log__c logRec, Boolean isError) {
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

    global class OrderWebhookException extends Exception {
    }
}
