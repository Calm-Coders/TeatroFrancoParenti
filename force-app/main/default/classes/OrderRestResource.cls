@RestResource(urlMapping='/v1/orders')
global without sharing class OrderRestResource {
    private static final Integer MAX_LOG_LENGTH = 131072;
    private static final Integer MAX_SECUTIX_LONG_TEXT_LENGTH = 32768;
    private static final String FLOW_NAME = 'OrderRestResource.receiveOrder';
    private static final String DEFAULT_ORDER_STATUS = 'Draft';
    private static final String FALLBACK_ACCOUNT_RECORD_TYPE = 'Fallback_Account';
    private static final String FALLBACK_ACCOUNT_NAME_PREFIX = 'Anonymous Secutix Account ';
    private static final String ORDER_OPERATION_OBJECT = 'Order_Operation_Data__c';
    private static final String ORDER_MOVEMENT_OBJECT = 'Order_Movement_Data__c';

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
        details.userInserted = toStringValue(rawDetailsMap.get('userInserted'));
        details.userUpdated = toStringValue(rawDetailsMap.get('userUpdated'));
        details.posNum = toStringValue(rawDetailsMap.get('posNum'));
        details.pointOfSalesId = toLongValue(rawDetailsMap.get('pointOfSalesId'));
        details.pointOfSalesCode = toStringValue(rawDetailsMap.get('pointOfSalesCode'));
        details.pointOfSalesName = toStringValue(rawDetailsMap.get('pointOfSalesName'));
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
            operation.operationId = toLongValue(rawOperation.get('operationId'));
            operation.parentOperationId = toLongValue(rawOperation.get('parentOperationId'));
            operation.parentOperationLinkType = toStringValue(rawOperation.get('parentOperationLinkType'));
            operation.kind = toStringValue(rawOperation.get('kind'));
            operation.type = toStringValue(rawOperation.get('type'));
            operation.quantity = toDecimalValue(rawOperation.get('quantity'));
            operation.basePrice = toDecimalValue(rawOperation.get('basePrice'));
            operation.unitPrice = toDecimalValue(rawOperation.get('unitPrice'));
            operation.withoutVatTotalAmount = toDecimalValue(rawOperation.get('withoutVatTotalAmount'));
            operation.totalAmount = toDecimalValue(rawOperation.get('totalAmount'));
            operation.productId = toLongValue(rawOperation.get('productId'));
            operation.product = toStringValue(rawOperation.get('product'));
            operation.productCode = toStringValue(rawOperation.get('productCode'));
            operation.itemId = toLongValue(rawOperation.get('itemId'));
            operation.performanceId = toLongValue(rawOperation.get('performanceId'));
            operation.performance = toStringValue(rawOperation.get('performance'));
            operation.eventId = toLongValue(rawOperation.get('eventId'));
            operation.physicalConfigurationId = toLongValue(rawOperation.get('physicalConfigurationId'));
            operation.siteId = toLongValue(rawOperation.get('siteId'));
            operation.site = toStringValue(rawOperation.get('site'));
            operation.siteAddress = buildSiteAddress(rawOperation.get('siteAddress'));
            operation.space = toStringValue(rawOperation.get('space'));
            operation.contingentId = toLongValue(rawOperation.get('contingentId'));
            operation.contingent = toStringValue(rawOperation.get('contingent'));
            operation.numbered = toBooleanValue(rawOperation.get('numbered'));
            operation.seatCategoryId = toLongValue(rawOperation.get('seatCategoryId'));
            operation.seatCategory = toStringValue(rawOperation.get('seatCategory'));
            operation.seatCategoryRank = toIntegerValue(rawOperation.get('seatCategoryRank'));
            operation.audienceSubCategoryId = toLongValue(rawOperation.get('audienceSubCategoryId'));
            operation.audienceSubCategory = toStringValue(rawOperation.get('audienceSubCategory'));
            operation.audienceSubCategoryRank = toIntegerValue(rawOperation.get('audienceSubCategoryRank'));
            operation.audienceSubCategoryRequireAttachment = toBooleanValue(rawOperation.get('audienceSubCategoryRequireAttachment'));
            operation.vatRate = toDecimalValue(rawOperation.get('vatRate'));
            operation.vatCountryCode = toStringValue(rawOperation.get('vatCountryCode'));
            operation.selfPaidVat = toBooleanValue(rawOperation.get('selfPaidVat'));
            operation.operationNumber = toIntegerValue(rawOperation.get('operationNumber'));
            operation.productFamilyType = toStringValue(rawOperation.get('productFamilyType'));
            operation.productFamilySubType = toStringValue(rawOperation.get('productFamilySubType'));
            operation.activityType = toStringValue(rawOperation.get('activityType'));
            operation.performanceDuration = toIntegerValue(rawOperation.get('performanceDuration'));
            operation.itemDisplayExternalDesignation = toStringValue(rawOperation.get('itemDisplayExternalDesignation'));
            operation.locations = buildLocationDatas(rawOperation.get('locations'));
            operation.fileId = toLongValue(rawOperation.get('fileId'));
            operation.waitingAccountBalance = toDecimalValue(rawOperation.get('waitingAccountBalance'));
            operation.season = toStringValue(rawOperation.get('season'));
            operation.seasonCode = toStringValue(rawOperation.get('seasonCode'));
            operation.seasonId = toLongValue(rawOperation.get('seasonId'));
            operation.crossSellParentOperationIds = toObjectList(rawOperation.get('crossSellParentOperationIds'));
            operation.comfortVariableValues = toObjectMap(rawOperation.get('comfortVariableValues'));
            operation.includedInShipmentFee = toBooleanValue(rawOperation.get('includedInShipmentFee'));
            operation.performanceCode = toStringValue(rawOperation.get('performanceCode'));
            operation.audienceCatId = toLongValue(rawOperation.get('audienceCatId'));
            operation.exchangeable = toBooleanValue(rawOperation.get('exchangeable'));
            operation.activityId = toLongValue(rawOperation.get('activityId'));
            operation.activityName = toStringValue(rawOperation.get('activityName'));
            operation.activityCode = toStringValue(rawOperation.get('activityCode'));
            operation.catalogCurrency = buildCatalogCurrency(rawOperation.get('catalogCurrency'));
            operation.expirationDate = toStringValue(rawOperation.get('expirationDate'));
            operation.championshipSeasonticket = toBooleanValue(rawOperation.get('championshipSeasonticket'));
            operation.fixedSeatSeasonticket = toBooleanValue(rawOperation.get('fixedSeatSeasonticket'));
            operation.allSeasonTicketLinesCompetition = toBooleanValue(rawOperation.get('allSeasonTicketLinesCompetition'));
            operation.insuredOperationIds = toObjectList(rawOperation.get('insuredOperationIds'));
            operation.resale = toBooleanValue(rawOperation.get('resale'));
            operation.isNominative = toBooleanValue(rawOperation.get('isNominative'));
            operation.nominative = toBooleanValue(rawOperation.get('nominative'));
            operation.priceComponentData = toObjectMap(rawOperation.get('priceComponentData'));
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
            movement.movementId = toLongValue(rawMovement.get('movementId'));
            movement.operationId = toLongValue(rawMovement.get('operationId'));
            movement.type = toStringValue(rawMovement.get('type'));
            movement.seatId = toLongValue(rawMovement.get('seatId'));
            movement.saleSeatId = toLongValue(rawMovement.get('saleSeatId'));
            movement.seatCategoryId = toLongValue(rawMovement.get('seatCategoryId'));
            movement.seatCategory = toStringValue(rawMovement.get('seatCategory'));
            movement.areaId = toLongValue(rawMovement.get('areaId'));
            movement.area = toStringValue(rawMovement.get('area'));
            movement.entranceId = toLongValue(rawMovement.get('entranceId'));
            movement.entrance = toStringValue(rawMovement.get('entrance'));
            movement.entranceCode = toStringValue(rawMovement.get('entranceCode'));
            movement.row = toStringValue(rawMovement.get('row'));
            movement.seatNumber = toStringValue(rawMovement.get('seatNumber'));
            movement.seatQualityId = toLongValue(rawMovement.get('seatQualityId'));
            movement.seatQuality = toStringValue(rawMovement.get('seatQuality'));
            movement.seatQualityCode = toStringValue(rawMovement.get('seatQualityCode'));
            movement.yCoordinate = toIntegerValue(rawMovement.get('yCoordinate'));
            movement.xCoordinate = toIntegerValue(rawMovement.get('xCoordinate'));
            movement.contingentId = toLongValue(rawMovement.get('contingentId'));
            movement.contingent = toStringValue(rawMovement.get('contingent'));
            movement.contactReference = toStringValue(rawMovement.get('contactReference'));
            movement.seatOrientation = toIntegerValue(rawMovement.get('seatOrientation'));
            movement.instanceNumber = toIntegerValue(rawMovement.get('instanceNumber'));
            movement.stageVisibility = toStringValue(rawMovement.get('stageVisibility'));
            movement.areaKind = toStringValue(rawMovement.get('areaKind'));
            movement.resumed = toBooleanValue(rawMovement.get('resumed'));
            movement.attributionMatch = toStringValue(rawMovement.get('attributionMatch'));
            movement.transferable = toBooleanValue(rawMovement.get('transferable'));
            movements.add(movement);
        }
        return movements;
    }

    private static OrderWrapper.SiteAddress buildSiteAddress(Object rawValue) {
        if (!(rawValue instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> rawMap = (Map<String, Object>) rawValue;
        OrderWrapper.SiteAddress siteAddress = new OrderWrapper.SiteAddress();
        siteAddress.firstAddressLine = toStringValue(rawMap.get('firstAddressLine'));
        siteAddress.zipCode = toStringValue(rawMap.get('zipCode'));
        siteAddress.locality = toStringValue(rawMap.get('locality'));
        siteAddress.countryCode = toStringValue(rawMap.get('countryCode'));
        return siteAddress;
    }

    private static List<OrderWrapper.LocationData> buildLocationDatas(Object rawValue) {
        List<OrderWrapper.LocationData> locations = new List<OrderWrapper.LocationData>();
        for (Object item : toObjectList(rawValue)) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> rawLocation = (Map<String, Object>) item;
            OrderWrapper.LocationData location = new OrderWrapper.LocationData();
            location.spaceCode = toStringValue(rawLocation.get('spaceCode'));
            location.siteCode = toStringValue(rawLocation.get('siteCode'));
            location.spaceExternalName = buildTranslationContainer(rawLocation.get('spaceExternalName'));
            location.siteExternalName = buildTranslationContainer(rawLocation.get('siteExternalName'));
            location.siteAddress = buildSiteAddress(rawLocation.get('siteAddress'));
            locations.add(location);
        }
        return locations;
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
        Id existingOrderId = resolveExistingOrderId(orderWrapper);
        Order orderRecord = buildOrder(orderWrapper, existingOrderId);
        if (existingOrderId == null) {
            insert orderRecord;
        } else {
            update orderRecord;
        }
        syncOrderChildren(orderWrapper, orderRecord.Id);
        return orderRecord;
    }

    private static Order buildOrder(OrderWrapper orderWrapper, Id existingOrderId) {
        OrderWrapper.OrderDetailsData details = orderWrapper.payload.orderDetailsData;
        Map<String, Object> rawDetails = rawOrderDetails(orderWrapper);
        String contactReference = firstContactReference(details);
        ResolvedContact resolvedContact = resolveContact(orderWrapper);
        Id accountId = resolveOrderAccountId(details);

        Order orderRecord = new Order();
        if (existingOrderId != null) {
            orderRecord.Id = existingOrderId;
        }
        orderRecord.EffectiveDate = resolveEffectiveDate(details);
        orderRecord.Status = DEFAULT_ORDER_STATUS;
        orderRecord.AccountId = accountId;
        orderRecord.BillToContactId = resolvedContact == null ? null : resolvedContact.contactId;
        orderRecord.ShipToContactId = resolvedContact == null ? null : resolvedContact.contactId;
        orderRecord.Type = truncateValue(details.orderType, 40);
        Long productId = firstInventoryProductId(details);
        setCustomField(
            orderRecord,
            'Product_Id__c',
            productId == null ? null : Decimal.valueOf(String.valueOf(productId))
        );
        setCustomField(orderRecord, 'Order_Id__c', truncateValue(details.orderId == null ? null : String.valueOf(details.orderId), 30));
        setCustomField(orderRecord, 'Order_Secret_Id__c', truncateValue(details.orderSecretId, 255));
        setCustomField(orderRecord, 'Order_State__c', truncateValue(details.orderState, 40));
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
        setCustomField(orderRecord, 'Movement_Ticket_Datas__c', serializeRawValue(rawDetails.get('movementTicketDatas'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Sales_Channel_Name__c', serializeRawValue(rawDetails.get('salesChannelName'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Generated_Contiguities__c', serializeRawValue(rawDetails.get('generatedContiguities'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Order_Origin_Data__c', serializeRawValue(rawDetails.get('orderOriginData'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Order_Installments__c', serializeRawValue(rawDetails.get('orderInstallmentsToCreate'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Catalog_Currency__c', serializeRawValue(rawDetails.get('catalogCurrency'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'Organization_Name__c', serializeRawValue(rawDetails.get('organizationName'), MAX_SECUTIX_LONG_TEXT_LENGTH));
        setCustomField(orderRecord, 'User_Inserted__c', truncateValue(details.userInserted, 80));
        setCustomField(orderRecord, 'User_Updated__c', truncateValue(details.userUpdated, 80));
        setCustomField(orderRecord, 'Pos_Num__c', truncateValue(details.posNum, 40));
        setCustomField(orderRecord, 'Point_Of_Sales_Id__c', decimalFromLong(details.pointOfSalesId));
        setCustomField(orderRecord, 'Point_Of_Sales_Code__c', truncateValue(details.pointOfSalesCode, 80));
        setCustomField(orderRecord, 'Point_Of_Sales_Name__c', truncateValue(details.pointOfSalesName, 255));
        setCustomField(orderRecord, 'Shipments__c', serializeRawValue(orderWrapper.rawPayload.get('shipments'), MAX_SECUTIX_LONG_TEXT_LENGTH));

        return orderRecord;
    }

    private static void syncOrderChildren(OrderWrapper orderWrapper, Id orderId) {
        if (orderId == null) {
            return;
        }

        deleteExistingOrderChildren(orderId);

        OrderWrapper.OrderDetailsData details = orderWrapper == null || orderWrapper.payload == null
            ? null
            : orderWrapper.payload.orderDetailsData;
        Map<String, Object> rawDetails = rawOrderDetails(orderWrapper);

        List<SObject> operationRecords = buildOperationRecords(orderId, details, rawDetails);
        if (!operationRecords.isEmpty()) {
            insert operationRecords;
        }

        Map<String, Id> operationRecordIdsByExternalId = new Map<String, Id>();
        List<SObject> operationsToUpdate = new List<SObject>();
        for (SObject operationRecord : operationRecords) {
            String operationExternalId = (String) operationRecord.get('Operation_Id__c');
            if (!String.isBlank(operationExternalId)) {
                operationRecordIdsByExternalId.put(operationExternalId, (Id) operationRecord.get('Id'));
            }
        }

        for (SObject operationRecord : operationRecords) {
            String parentOperationExternalId = (String) operationRecord.get('Parent_Operation_Id__c');
            if (String.isBlank(parentOperationExternalId)) {
                continue;
            }

            Id parentOperationRecordId = operationRecordIdsByExternalId.get(parentOperationExternalId);
            if (parentOperationRecordId == null) {
                continue;
            }

            operationRecord.put('Parent_Operation__c', parentOperationRecordId);
            operationsToUpdate.add(operationRecord);
        }

        if (!operationsToUpdate.isEmpty()) {
            update operationsToUpdate;
        }

        List<SObject> movementRecords = buildMovementRecords(orderId, details, rawDetails, operationRecordIdsByExternalId);
        if (!movementRecords.isEmpty()) {
            insert movementRecords;
        }
    }

    private static void deleteExistingOrderChildren(Id orderId) {
        List<SObject> movementRecords = Database.query(
            'SELECT Id FROM ' + ORDER_MOVEMENT_OBJECT + ' WHERE Order__c = :orderId'
        );
        if (!movementRecords.isEmpty()) {
            delete movementRecords;
        }

        List<SObject> operationRecords = Database.query(
            'SELECT Id FROM ' + ORDER_OPERATION_OBJECT + ' WHERE Order__c = :orderId'
        );
        if (!operationRecords.isEmpty()) {
            delete operationRecords;
        }
    }

    private static List<SObject> buildOperationRecords(
        Id orderId,
        OrderWrapper.OrderDetailsData details,
        Map<String, Object> rawDetails
    ) {
        List<SObject> operationRecords = new List<SObject>();
        List<OrderWrapper.OperationData> operations = details == null ? null : details.operationDatas;
        List<Object> rawOperations = toObjectList(rawDetails.get('operationDatas'));
        Integer operationCount = operations == null ? 0 : operations.size();

        for (Integer i = 0; i < operationCount; i++) {
            OrderWrapper.OperationData operation = operations[i];
            Map<String, Object> rawOperation = i < rawOperations.size() && rawOperations[i] instanceof Map<String, Object>
                ? (Map<String, Object>) rawOperations[i]
                : new Map<String, Object>();
            SObject operationRecord = instantiateSObject(ORDER_OPERATION_OBJECT);

            setCustomField(operationRecord, 'Order__c', orderId);
            setCustomField(operationRecord, 'Inventory__c', resolveInventoryLookupId(operation == null ? null : operation.productId));
            setCustomField(operationRecord, 'Operation_Id__c', stringifyLong(operation == null ? null : operation.operationId));
            setCustomField(operationRecord, 'Parent_Operation_Id__c', stringifyLong(operation == null ? null : operation.parentOperationId));
            setCustomField(operationRecord, 'Parent_Operation_Link_Type__c', truncateValue(operation == null ? null : operation.parentOperationLinkType, 80));
            setCustomField(operationRecord, 'Kind__c', truncateValue(operation == null ? null : operation.kind, 80));
            setCustomField(operationRecord, 'Type__c', truncateValue(operation == null ? null : operation.type, 80));
            setCustomField(operationRecord, 'Quantity__c', operation == null ? null : operation.quantity);
            setCustomField(operationRecord, 'Base_Price__c', operation == null ? null : operation.basePrice);
            setCustomField(operationRecord, 'Unit_Price__c', operation == null ? null : operation.unitPrice);
            setCustomField(operationRecord, 'Without_Vat_Total_Amount__c', operation == null ? null : operation.withoutVatTotalAmount);
            setCustomField(operationRecord, 'Total_Amount__c', operation == null ? null : operation.totalAmount);
            setCustomField(operationRecord, 'Product_Id__c', decimalFromLong(operation == null ? null : operation.productId));
            setCustomField(operationRecord, 'Product__c', truncateValue(operation == null ? null : operation.product, 255));
            setCustomField(operationRecord, 'Product_Code__c', truncateValue(operation == null ? null : operation.productCode, 80));
            setCustomField(operationRecord, 'Item_Id__c', decimalFromLong(operation == null ? null : operation.itemId));
            setCustomField(operationRecord, 'Performance_Id__c', decimalFromLong(operation == null ? null : operation.performanceId));
            setCustomField(operationRecord, 'Performance__c', truncateValue(operation == null ? null : operation.performance, 255));
            setCustomField(operationRecord, 'Event_Id__c', decimalFromLong(operation == null ? null : operation.eventId));
            setCustomField(operationRecord, 'Physical_Configuration_Id__c', decimalFromLong(operation == null ? null : operation.physicalConfigurationId));
            setCustomField(operationRecord, 'Site_Id__c', decimalFromLong(operation == null ? null : operation.siteId));
            setCustomField(operationRecord, 'Site__c', truncateValue(operation == null ? null : operation.site, 255));
            setCustomField(operationRecord, 'Space__c', truncateValue(operation == null ? null : operation.space, 255));
            setCustomField(operationRecord, 'Contingent__c', truncateValue(operation == null ? null : operation.contingent, 255));
            setCustomField(operationRecord, 'Numbered__c', operation == null ? null : operation.numbered);
            setCustomField(operationRecord, 'Seat_Category_Id__c', decimalFromLong(operation == null ? null : operation.seatCategoryId));
            setCustomField(operationRecord, 'Seat_Category__c', truncateValue(operation == null ? null : operation.seatCategory, 255));
            setCustomField(operationRecord, 'Seat_Category_Rank__c', operation == null || operation.seatCategoryRank == null ? null : Decimal.valueOf(String.valueOf(operation.seatCategoryRank)));
            setCustomField(operationRecord, 'Audience_SubCategory_Id__c', decimalFromLong(operation == null ? null : operation.audienceSubCategoryId));
            setCustomField(operationRecord, 'Audience_SubCategory__c', truncateValue(operation == null ? null : operation.audienceSubCategory, 255));
            setCustomField(operationRecord, 'Audience_SubCategory_Rank__c', operation == null || operation.audienceSubCategoryRank == null ? null : Decimal.valueOf(String.valueOf(operation.audienceSubCategoryRank)));
            setCustomField(operationRecord, 'Audience_SubCategory_Require_Attachment__c', operation == null ? null : operation.audienceSubCategoryRequireAttachment);
            setCustomField(operationRecord, 'Vat_Rate__c', operation == null ? null : operation.vatRate);
            setCustomField(operationRecord, 'Vat_Country_Code__c', truncateValue(operation == null ? null : operation.vatCountryCode, 10));
            setCustomField(operationRecord, 'Self_Paid_Vat__c', operation == null ? null : operation.selfPaidVat);
            setCustomField(operationRecord, 'Operation_Number__c', operation == null || operation.operationNumber == null ? null : Decimal.valueOf(String.valueOf(operation.operationNumber)));
            setCustomField(operationRecord, 'Product_Family_Type__c', truncateValue(operation == null ? null : operation.productFamilyType, 80));
            setCustomField(operationRecord, 'Product_Family_SubType__c', truncateValue(operation == null ? null : operation.productFamilySubType, 80));
            setCustomField(operationRecord, 'Activity_Type__c', truncateValue(operation == null ? null : operation.activityType, 80));
            setCustomField(operationRecord, 'Performance_Date__c', truncateValue(operation == null ? null : operation.itemDate, 40));
            setCustomField(operationRecord, 'Performance_Duration__c', operation == null || operation.performanceDuration == null ? null : Decimal.valueOf(String.valueOf(operation.performanceDuration)));
            setCustomField(operationRecord, 'Expiration_Date__c', truncateValue(operation == null ? null : operation.expirationDate, 40));
            setCustomField(operationRecord, 'Item_Display_External_Designation__c', truncateValue(operation == null ? null : operation.itemDisplayExternalDesignation, 255));
            setCustomField(operationRecord, 'File_Id__c', decimalFromLong(operation == null ? null : operation.fileId));
            setCustomField(operationRecord, 'Waiting_Account_Balance__c', operation == null ? null : operation.waitingAccountBalance);
            setCustomField(operationRecord, 'Season__c', truncateValue(operation == null ? null : operation.season, 255));
            setCustomField(operationRecord, 'Season_Code__c', truncateValue(operation == null ? null : operation.seasonCode, 80));
            setCustomField(operationRecord, 'Season_Id__c', decimalFromLong(operation == null ? null : operation.seasonId));
            setCustomField(operationRecord, 'Cross_Sell_Parent_Operation_Ids__c', serializeRawValue(rawOperation.get('crossSellParentOperationIds'), MAX_SECUTIX_LONG_TEXT_LENGTH));
            setCustomField(operationRecord, 'Comfort_Variable_Values__c', serializeRawValue(rawOperation.get('comfortVariableValues'), MAX_SECUTIX_LONG_TEXT_LENGTH));
            setCustomField(operationRecord, 'Performance_Code__c', truncateValue(operation == null ? null : operation.performanceCode, 80));
            setCustomField(operationRecord, 'Audience_Cat_Id__c', decimalFromLong(operation == null ? null : operation.audienceCatId));
            setCustomField(operationRecord, 'Exchangeable__c', operation == null ? null : operation.exchangeable);
            setCustomField(operationRecord, 'Activity_Id__c', decimalFromLong(operation == null ? null : operation.activityId));
            setCustomField(operationRecord, 'Activity_Name__c', truncateValue(operation == null ? null : operation.activityName, 255));
            setCustomField(operationRecord, 'Activity_Code__c', truncateValue(operation == null ? null : operation.activityCode, 80));
            setCustomField(operationRecord, 'Included_In_Shipment_Fee__c', operation == null ? null : operation.includedInShipmentFee);
            setCustomField(operationRecord, 'Catalog_Currency__c', serializeRawValue(rawOperation.get('catalogCurrency'), MAX_SECUTIX_LONG_TEXT_LENGTH));
            setCustomField(operationRecord, 'Championship_Seasonticket__c', operation == null ? null : operation.championshipSeasonticket);
            setCustomField(operationRecord, 'Fixed_Seat_Seasonticket__c', operation == null ? null : operation.fixedSeatSeasonticket);
            setCustomField(operationRecord, 'All_Season_Ticket_Lines_Competition__c', operation == null ? null : operation.allSeasonTicketLinesCompetition);
            setCustomField(operationRecord, 'Insured_Operation_Ids__c', serializeRawValue(rawOperation.get('insuredOperationIds'), MAX_SECUTIX_LONG_TEXT_LENGTH));
            setCustomField(operationRecord, 'Resale__c', operation == null ? null : operation.resale);
            setCustomField(operationRecord, 'Is_Nominative__c', operation == null ? null : operation.isNominative);
            setCustomField(operationRecord, 'Nominative__c', operation == null ? null : operation.nominative);
            setCustomField(operationRecord, 'Site_Address__c', serializeRawValue(rawOperation.get('siteAddress'), MAX_SECUTIX_LONG_TEXT_LENGTH));
            setCustomField(operationRecord, 'Locations__c', serializeRawValue(rawOperation.get('locations'), MAX_SECUTIX_LONG_TEXT_LENGTH));
            operationRecords.add(operationRecord);
        }

        return operationRecords;
    }

    private static List<SObject> buildMovementRecords(
        Id orderId,
        OrderWrapper.OrderDetailsData details,
        Map<String, Object> rawDetails,
        Map<String, Id> operationRecordIdsByExternalId
    ) {
        List<SObject> movementRecords = new List<SObject>();
        List<OrderWrapper.MovementData> movements = details == null ? null : details.movementDatas;
        List<Object> rawMovements = toObjectList(rawDetails.get('movementDatas'));
        Integer movementCount = movements == null ? 0 : movements.size();

        for (Integer i = 0; i < movementCount; i++) {
            OrderWrapper.MovementData movement = movements[i];
            Map<String, Object> rawMovement = i < rawMovements.size() && rawMovements[i] instanceof Map<String, Object>
                ? (Map<String, Object>) rawMovements[i]
                : new Map<String, Object>();
            SObject movementRecord = instantiateSObject(ORDER_MOVEMENT_OBJECT);
            String operationExternalId = stringifyLong(movement == null ? null : movement.operationId);

            setCustomField(movementRecord, 'Order__c', orderId);
            setCustomField(movementRecord, 'Account__c', resolveAccountIdByContactNumber(movement == null ? null : movement.contactReference));
            setCustomField(movementRecord, 'Order_Operation_Data__c', operationRecordIdsByExternalId.get(operationExternalId));
            setCustomField(movementRecord, 'Movement_Id__c', stringifyLong(movement == null ? null : movement.movementId));
            setCustomField(movementRecord, 'Operation_Id__c', operationExternalId);
            setCustomField(movementRecord, 'Type__c', truncateValue(movement == null ? null : movement.type, 80));
            setCustomField(movementRecord, 'Seat_Id__c', decimalFromLong(movement == null ? null : movement.seatId));
            setCustomField(movementRecord, 'Sale_Seat_Id__c', decimalFromLong(movement == null ? null : movement.saleSeatId));
            setCustomField(movementRecord, 'Seat_Category_Id__c', decimalFromLong(movement == null ? null : movement.seatCategoryId));
            setCustomField(movementRecord, 'Seat_Category__c', truncateValue(movement == null ? null : movement.seatCategory, 255));
            setCustomField(movementRecord, 'Area_Id__c', decimalFromLong(movement == null ? null : movement.areaId));
            setCustomField(movementRecord, 'Area__c', truncateValue(movement == null ? null : movement.area, 255));
            setCustomField(movementRecord, 'Entrance_Id__c', decimalFromLong(movement == null ? null : movement.entranceId));
            setCustomField(movementRecord, 'Entrance__c', truncateValue(movement == null ? null : movement.entrance, 255));
            setCustomField(movementRecord, 'Entrance_Code__c', truncateValue(movement == null ? null : movement.entranceCode, 80));
            setCustomField(movementRecord, 'Row__c', truncateValue(movement == null ? null : movement.row, 80));
            setCustomField(movementRecord, 'Seat_Number__c', truncateValue(movement == null ? null : movement.seatNumber, 80));
            setCustomField(movementRecord, 'Seat_Quality_Id__c', decimalFromLong(movement == null ? null : movement.seatQualityId));
            setCustomField(movementRecord, 'Seat_Quality__c', truncateValue(movement == null ? null : movement.seatQuality, 255));
            setCustomField(movementRecord, 'Seat_Quality_Code__c', truncateValue(movement == null ? null : movement.seatQualityCode, 80));
            setCustomField(movementRecord, 'Y_Coordinate__c', movement == null || movement.yCoordinate == null ? null : Decimal.valueOf(String.valueOf(movement.yCoordinate)));
            setCustomField(movementRecord, 'X_Coordinate__c', movement == null || movement.xCoordinate == null ? null : Decimal.valueOf(String.valueOf(movement.xCoordinate)));
            setCustomField(movementRecord, 'Contact_Reference__c', truncateValue(movement == null ? null : movement.contactReference, 80));
            setCustomField(movementRecord, 'Stage_Visibility__c', truncateValue(movement == null ? null : movement.stageVisibility, 80));
            setCustomField(movementRecord, 'Area_Kind__c', truncateValue(movement == null ? null : movement.areaKind, 80));
            setCustomField(movementRecord, 'Resumed__c', movement == null ? null : movement.resumed);
            setCustomField(movementRecord, 'Attribution_Match__c', truncateValue(movement == null ? null : movement.attributionMatch, 80));
            movementRecords.add(movementRecord);
        }

        return movementRecords;
    }

    private static Id resolveExistingOrderId(OrderWrapper orderWrapper) {
        OrderWrapper.OrderDetailsData details = orderWrapper == null || orderWrapper.payload == null
            ? null
            : orderWrapper.payload.orderDetailsData;

        String externalOrderId = truncateValue(details == null || details.orderId == null ? null : String.valueOf(details.orderId), 30);
        String externalOrderSecretId = truncateValue(details == null ? null : details.orderSecretId, 255);

        if (String.isBlank(externalOrderId) && String.isBlank(externalOrderSecretId)) {
            return null;
        }

        List<Order> matchingOrders;
        if (!String.isBlank(externalOrderId) && !String.isBlank(externalOrderSecretId)) {
            matchingOrders = [
                SELECT Id, Order_Id__c, Order_Secret_Id__c
                FROM Order
                WHERE Order_Id__c = :externalOrderId
                   OR Order_Secret_Id__c = :externalOrderSecretId
                LIMIT 3
            ];
        } else if (!String.isBlank(externalOrderId)) {
            matchingOrders = [
                SELECT Id, Order_Id__c, Order_Secret_Id__c
                FROM Order
                WHERE Order_Id__c = :externalOrderId
                LIMIT 3
            ];
        } else {
            matchingOrders = [
                SELECT Id, Order_Id__c, Order_Secret_Id__c
                FROM Order
                WHERE Order_Secret_Id__c = :externalOrderSecretId
                LIMIT 3
            ];
        }

        if (matchingOrders.isEmpty()) {
            return null;
        }

        Set<Id> matchingOrderIds = new Set<Id>();
        for (Order orderRecord : matchingOrders) {
            matchingOrderIds.add(orderRecord.Id);
        }

        if (matchingOrderIds.size() > 1) {
            throw new OrderWebhookException(
                'Multiple existing orders found for orderId ' + externalOrderId +
                ' / orderSecretId ' + externalOrderSecretId + '.'
            );
        }

        return matchingOrders[0].Id;
    }

    private static Id resolveInventoryLookupId(Long productId) {
        if (productId == null) {
            return null;
        }

        List<Inventory__c> matchingInventories = [
            SELECT Id
            FROM Inventory__c
            WHERE Inventory_Id__c = :productId
            ORDER BY LastModifiedDate DESC, CreatedDate DESC, Id DESC
            LIMIT 1
        ];

        if (matchingInventories.isEmpty()) {
            return null;
        }

        return matchingInventories[0].Id;
    }

    private static Long firstInventoryProductId(OrderWrapper.OrderDetailsData details) {
        if (details == null || details.operationDatas == null) {
            return null;
        }

        Long fallbackProductId;
        for (OrderWrapper.OperationData operation : details.operationDatas) {
            if (operation == null || operation.productId == null) {
                continue;
            }

            if (fallbackProductId == null) {
                fallbackProductId = operation.productId;
            }

            if (!'CHARGES'.equalsIgnoreCase(operation.kind)) {
                return operation.productId;
            }
        }

        return fallbackProductId;
    }

    private static Id resolveOrderAccountId(OrderWrapper.OrderDetailsData details) {
        Id topLevelContactAccountId = resolveAccountIdByContactNumber(orderLevelContactReference(details));
        if (topLevelContactAccountId != null) {
            return topLevelContactAccountId;
        }

        return resolveFallbackOrderAccountId();
    }

    private static Id resolveFallbackOrderAccountId() {
        Id fallbackAccountId = resolveFallbackAccountId();
        if (fallbackAccountId == null) {
            throw new OrderWebhookException(
                'No fallback account is configured for record type ' +
                FALLBACK_ACCOUNT_RECORD_TYPE +
                '.'
            );
        }

        return fallbackAccountId;
    }

    private static Id resolveAccountIdByContactNumber(String contactNumber) {
        String normalizedContactNumber = truncateValue(contactNumber, 80);
        if (String.isBlank(normalizedContactNumber)) {
            return null;
        }

        List<Account> matchingAccounts = [
            SELECT Id
            FROM Account
            WHERE Contact_Number__c = :normalizedContactNumber
            ORDER BY LastModifiedDate DESC, CreatedDate DESC, Id DESC
            LIMIT 1
        ];

        return matchingAccounts.isEmpty() ? null : matchingAccounts[0].Id;
    }

    private static ResolvedContact resolveContact(OrderWrapper orderWrapper) {
        String contactNumber = firstResolvedContactNumber(orderWrapper);
        if (String.isBlank(contactNumber)) {
            return null;
        }

        List<Contact> contacts = [
            SELECT Id, AccountId
            FROM Contact
            WHERE Contact_Number__c = :contactNumber
            LIMIT 2
        ];

        if (contacts.size() > 1) {
            throw new OrderWebhookException('Multiple contacts found for contactNumber ' + contactNumber + '.');
        }

        if (contacts.isEmpty()) {
            return null;
        }

        return new ResolvedContact(contacts[0].Id, contacts[0].AccountId);
    }

    private static Id resolveFallbackAccountId() {
        Id fallbackRecordTypeId = fallbackAccountRecordTypeId();
        if (fallbackRecordTypeId == null) {
            return null;
        }

        String fallbackAccountName = fallbackAccountNameForDate(Date.today());
        List<Account> fallbackAccounts = [
            SELECT Id
            FROM Account
            WHERE RecordTypeId = :fallbackRecordTypeId
              AND Name = :fallbackAccountName
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT 1
        ];

        if (!fallbackAccounts.isEmpty()) {
            return fallbackAccounts[0].Id;
        }

        Account fallbackAccount = new Account(
            Name = fallbackAccountName,
            RecordTypeId = fallbackRecordTypeId
        );
        insert fallbackAccount;
        return fallbackAccount.Id;
    }

    private static Id fallbackAccountRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo fallbackRecordType = recordTypesByDeveloperName.get(FALLBACK_ACCOUNT_RECORD_TYPE);
        return fallbackRecordType == null ? null : fallbackRecordType.getRecordTypeId();
    }

    private static String fallbackAccountNameForDate(Date targetDate) {
        Date normalizedDate = targetDate == null ? Date.today() : targetDate;
        String monthValue = normalizedDate.month() == null
            ? '00'
            : String.valueOf(normalizedDate.month()).leftPad(2, '0');
        return FALLBACK_ACCOUNT_NAME_PREFIX + monthValue + ' - ' + String.valueOf(normalizedDate.year());
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

    private static String orderLevelContactReference(OrderWrapper.OrderDetailsData details) {
        return details == null ? null : details.contactReference;
    }

    private static String firstContactReference(OrderWrapper.OrderDetailsData details) {
        if (details == null) {
            return null;
        }

        if (details.movementDatas != null) {
            for (OrderWrapper.MovementData movement : details.movementDatas) {
                if (movement != null && !String.isBlank(movement.contactReference)) {
                    return movement.contactReference;
                }
            }
        }

        if (!String.isBlank(details.contactReference)) {
            return details.contactReference;
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

    private static Map<String, Object> toObjectMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    private static SObject instantiateSObject(String objectApiName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            throw new OrderWebhookException('Missing required object metadata: ' + objectApiName + '.');
        }

        return objectType.newSObject();
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

    private static String stringifyLong(Long value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Decimal decimalFromLong(Long value) {
        return value == null ? null : Decimal.valueOf(String.valueOf(value));
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

    private class ResolvedContact {
        private Id contactId;
        private Id accountId;

        private ResolvedContact(Id contactId, Id accountId) {
            this.contactId = contactId;
            this.accountId = accountId;
        }
    }
}
