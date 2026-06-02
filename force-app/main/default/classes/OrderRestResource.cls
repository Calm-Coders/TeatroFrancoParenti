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
        orderWrapper.payload = buildPayload(rawPayloadMap);
        return orderWrapper;
    }

    private static OrderWrapper.Payload buildPayload(Map<String, Object> rawPayloadMap) {
        OrderWrapper.Payload payload = new OrderWrapper.Payload();
        payload.orderDetailGranularity = toStringValue(rawPayloadMap.get('orderDetailGranularity'));

        Object rawDetails = rawPayloadMap.get('orderDetailsData');
        if (rawDetails != null) {
            if (!(rawDetails instanceof Map<String, Object>)) {
                throw new OrderWebhookException('The orderDetailsData node must be a valid JSON object.');
            }
            payload.orderDetailsData = buildOrderDetailsData((Map<String, Object>) rawDetails);
        }

        return payload;
    }

    private static OrderWrapper.OrderDetailsData buildOrderDetailsData(Map<String, Object> rawDetailsMap) {
        OrderWrapper.OrderDetailsData details = new OrderWrapper.OrderDetailsData();
        details.orderId = toLongValue(rawDetailsMap.get('orderId'));
        details.orderState = toStringValue(rawDetailsMap.get('orderState'));
        details.creationDateTime = toStringValue(rawDetailsMap.get('creationDateTime'));
        details.referenceDate = toStringValue(rawDetailsMap.get('referenceDate'));
        details.expirationDate = toStringValue(rawDetailsMap.get('expirationDate'));
        details.saleAmount = toDecimalValue(rawDetailsMap.get('saleAmount'));
        details.preSaleAmount = toDecimalValue(rawDetailsMap.get('preSaleAmount'));
        details.reservationAmount = toDecimalValue(rawDetailsMap.get('reservationAmount'));
        details.optionAmount = toDecimalValue(rawDetailsMap.get('optionAmount'));
        details.waitingAccountBalanceAmount = toDecimalValue(rawDetailsMap.get('waitingAccountBalanceAmount'));
        details.operationDatas = buildOperationDatas(rawDetailsMap.get('operationDatas'));
        details.movementDatas = buildMovementDatas(rawDetailsMap.get('movementDatas'));
        details.movementTicketDatas = buildMovementTicketDatas(rawDetailsMap.get('movementTicketDatas'));
        details.contactReference = toStringValue(rawDetailsMap.get('contactReference'));
        details.salesChannelName = buildTranslationContainer(rawDetailsMap.get('salesChannelName'));
        details.orderType = toStringValue(rawDetailsMap.get('orderType'));
        details.generatedContiguities = toObjectList(rawDetailsMap.get('generatedContiguities'));
        details.orderOriginData = buildOrderOriginData(rawDetailsMap.get('orderOriginData'));
        details.salesChannelType = toStringValue(rawDetailsMap.get('salesChannelType'));
        details.orderInstallmentsToCreate = toObjectList(rawDetailsMap.get('orderInstallmentsToCreate'));
        details.orderSecretId = toStringValue(rawDetailsMap.get('orderSecretId'));
        details.orderOriginator = toStringValue(rawDetailsMap.get('orderOriginator'));
        details.salesChannelCode = toStringValue(rawDetailsMap.get('salesChannelCode'));
        details.catalogCurrency = buildCatalogCurrency(rawDetailsMap.get('catalogCurrency'));
        details.organizationCode = toStringValue(rawDetailsMap.get('organizationCode'));
        details.organizationName = buildTranslationContainer(rawDetailsMap.get('organizationName'));
        details.multicurrency = toBooleanValue(rawDetailsMap.get('multicurrency'));
        return details;
    }

    private static List<OrderWrapper.OperationData> buildOperationDatas(Object rawValue) {
        List<OrderWrapper.OperationData> operations = new List<OrderWrapper.OperationData>();
        for (Object item : toObjectList(rawValue)) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> rawOperation = (Map<String, Object>) item;
            OrderWrapper.OperationData operation = new OrderWrapper.OperationData();
            operation.product = toStringValue(rawOperation.get('product'));
            operation.site = toStringValue(rawOperation.get('site'));
            operation.itemDate = toStringValue(rawOperation.get('itemDate'));
            if (String.isBlank(operation.itemDate)) {
                operation.itemDate = toStringValue(rawOperation.get('performanceDate'));
            }
            operations.add(operation);
        }
        return operations;
    }

    private static List<OrderWrapper.MovementData> buildMovementDatas(Object rawValue) {
        List<OrderWrapper.MovementData> movements = new List<OrderWrapper.MovementData>();
        for (Object item : toObjectList(rawValue)) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> rawMovement = (Map<String, Object>) item;
            OrderWrapper.MovementData movement = new OrderWrapper.MovementData();
            movement.contactReference = toStringValue(rawMovement.get('contactReference'));
            movements.add(movement);
        }
        return movements;
    }

    private static List<OrderWrapper.MovementTicketData> buildMovementTicketDatas(Object rawValue) {
        List<OrderWrapper.MovementTicketData> movementTickets = new List<OrderWrapper.MovementTicketData>();
        for (Object item : toObjectList(rawValue)) {
            if (item instanceof Map<String, Object>) {
                movementTickets.add(new OrderWrapper.MovementTicketData());
            }
        }
        return movementTickets;
    }

    private static OrderWrapper.TranslationContainer buildTranslationContainer(Object rawValue) {
        if (!(rawValue instanceof Map<String, Object>)) {
            return null;
        }

        OrderWrapper.TranslationContainer container = new OrderWrapper.TranslationContainer();
        container.translations = new List<OrderWrapper.TranslationValue>();

        Map<String, Object> rawMap = (Map<String, Object>) rawValue;
        for (Object item : toObjectList(rawMap.get('translations'))) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> rawTranslation = (Map<String, Object>) item;
            OrderWrapper.TranslationValue translation = new OrderWrapper.TranslationValue();
            translation.locale = toStringValue(rawTranslation.get('locale'));
            translation.value = toStringValue(rawTranslation.get('value'));
            container.translations.add(translation);
        }

        return container;
    }

    private static OrderWrapper.OrderOriginData buildOrderOriginData(Object rawValue) {
        if (!(rawValue instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> rawMap = (Map<String, Object>) rawValue;
        OrderWrapper.OrderOriginData orderOriginData = new OrderWrapper.OrderOriginData();
        orderOriginData.toCreateToken = toBooleanValue(rawMap.get('toCreateToken'));
        return orderOriginData;
    }

    private static OrderWrapper.CatalogCurrency buildCatalogCurrency(Object rawValue) {
        if (!(rawValue instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> rawMap = (Map<String, Object>) rawValue;
        OrderWrapper.CatalogCurrency catalogCurrency = new OrderWrapper.CatalogCurrency();
        catalogCurrency.currencyCode = toStringValue(rawMap.get('currencyCode'));
        catalogCurrency.symbol = toStringValue(rawMap.get('symbol'));
        catalogCurrency.fractionDigit = toIntegerValue(rawMap.get('fractionDigit'));
        catalogCurrency.minAmount = toDecimalValue(rawMap.get('minAmount'));
        return catalogCurrency;
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
        Map<String, Object> rawDetails = rawOrderDetails(orderWrapper);
        String contactReference = firstContactReference(details);
        Id contactId = resolveContactId(orderWrapper);

        Order orderRecord = new Order();
        orderRecord.EffectiveDate = resolveEffectiveDate(details);
        orderRecord.Status = DEFAULT_ORDER_STATUS;
        orderRecord.Description = buildDescription(orderWrapper);
        orderRecord.BillToContactId = contactId;
        orderRecord.ShipToContactId = contactId;
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
        setCustomField(orderRecord, 'Operation_Datas__c', serializeRawValue(rawDetails.get('operationDatas'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Movement_Datas__c', serializeRawValue(rawDetails.get('movementDatas'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Movement_Ticket_Datas__c', serializeRawValue(rawDetails.get('movementTicketDatas'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Sales_Channel_Name__c', serializeRawValue(rawDetails.get('salesChannelName'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Generated_Contiguities__c', serializeRawValue(rawDetails.get('generatedContiguities'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Order_Origin_Data__c', serializeRawValue(rawDetails.get('orderOriginData'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Order_Installments__c', serializeRawValue(rawDetails.get('orderInstallmentsToCreate'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Catalog_Currency__c', serializeRawValue(rawDetails.get('catalogCurrency'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Organization_Name__c', serializeRawValue(rawDetails.get('organizationName'), MAX_SECUTIX_LONG_TEXT_LENGTH));

        return orderRecord;
    }

    private static Id resolveContactId(OrderWrapper orderWrapper) {
        String contactNumber = firstResolvedContactNumber(orderWrapper);
        if (String.isBlank(contactNumber)) {
            return null;
        }

        List<Contact> contacts = [
            SELECT Id
            FROM Contact
            WHERE Contact_Number__c = :contactNumber
            LIMIT 2
        ];

        if (contacts.size() > 1) {
            throw new OrderWebhookException('Multiple contacts found for contactNumber ' + contactNumber + '.');
        }

        return contacts.isEmpty() ? null : contacts[0].Id;
    }

    private static String firstResolvedContactNumber(OrderWrapper orderWrapper) {
        String shipmentContactNumber = firstShipmentContactNumber(orderWrapper);
        if (!String.isBlank(shipmentContactNumber)) {
            return shipmentContactNumber;
        }

        OrderWrapper.OrderDetailsData details = orderWrapper == null || orderWrapper.payload == null
            ? null
            : orderWrapper.payload.orderDetailsData;
        return firstContactReference(details);
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

    private static String firstShipmentContactNumber(OrderWrapper orderWrapper) {
        if (orderWrapper == null || orderWrapper.rawPayload == null) {
            return null;
        }

        for (Object shipmentItem : toObjectList(orderWrapper.rawPayload.get('shipments'))) {
            if (!(shipmentItem instanceof Map<String, Object>)) {
                continue;
            }

            String contactNumber = toStringValue(((Map<String, Object>) shipmentItem).get('contactNumber'));
            if (!String.isBlank(contactNumber)) {
                return contactNumber;
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

    private static Map<String, Object> rawOrderDetails(OrderWrapper orderWrapper) {
        if (orderWrapper == null || orderWrapper.rawPayload == null) {
            return new Map<String, Object>();
        }

        Object rawDetails = orderWrapper.rawPayload.get('orderDetailsData');
        return rawDetails instanceof Map<String, Object> ? (Map<String, Object>) rawDetails : new Map<String, Object>();
    }

    private static String toStringValue(Object value) {
        if (value == null) {
            return null;
        }
        return value instanceof String ? (String) value : String.valueOf(value);
    }

    private static Decimal toDecimalValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf(String.valueOf((Integer) value));
        }
        if (value instanceof Long) {
            return Decimal.valueOf(String.valueOf((Long) value));
        }
        if (value instanceof Double) {
            return Decimal.valueOf(String.valueOf((Double) value));
        }
        if (value instanceof String && !String.isBlank((String) value)) {
            return Decimal.valueOf((String) value);
        }
        return null;
    }

    private static Long toLongValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Long) {
            return (Long) value;
        }
        if (value instanceof Integer) {
            return Long.valueOf(String.valueOf((Integer) value));
        }
        if (value instanceof Decimal) {
            return Long.valueOf(String.valueOf(((Decimal) value).longValue()));
        }
        if (value instanceof Double) {
            return Long.valueOf(String.valueOf(((Double) value).longValue()));
        }
        if (value instanceof String && !String.isBlank((String) value)) {
            return Long.valueOf((String) value);
        }
        return null;
    }

    private static Integer toIntegerValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Long) {
            return Integer.valueOf(String.valueOf((Long) value));
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).intValue();
        }
        if (value instanceof Double) {
            return ((Double) value).intValue();
        }
        if (value instanceof String && !String.isBlank((String) value)) {
            return Integer.valueOf((String) value);
        }
        return null;
    }

    private static Boolean toBooleanValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        if (value instanceof String && !String.isBlank((String) value)) {
            return 'true'.equalsIgnoreCase((String) value);
        }
        return null;
    }

    private static List<Object> toObjectList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
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
