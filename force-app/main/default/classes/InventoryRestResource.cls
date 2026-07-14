@RestResource(urlMapping='/v1/inventories')
global without sharing class InventoryRestResource {
    private static final Integer MAX_LOG_LENGTH = 131072;
    // Long-text serialization cap. 32,768 silently truncated large event/seasonTicket/pack
    // payloads (observed up to ~123k chars in prod logs); 131,072 is the platform max.
    // setCustomField still truncates to each field's actual configured length.
    private static final Integer MAX_LONG_TEXT_LENGTH = 131072;
    private static final String FLOW_NAME = 'InventoryRestResource.receiveInventory';
    private static final String SIMPLE_TICKET_SUBTYPE = 'SIMPLE_TICKET';

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
                products = dedupePayloadsById(deserializePayloads(rawBody));
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
            List<Inventory__c> inventoryRecords = new List<Inventory__c>();

            for (InventoryWrapper inventoryWrapper : products) {
                validatePayload(inventoryWrapper);
                inventoryRecords.add(buildInventoryRecord(inventoryWrapper));

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

            // Upsert on the unique external id so concurrent webhook calls for the
            // same product collide at database level instead of creating duplicates.
            List<Inventory__c> recordsWithExternalId = new List<Inventory__c>();
            List<Inventory__c> recordsWithoutExternalId = new List<Inventory__c>();
            for (Inventory__c inventoryRecord : inventoryRecords) {
                if (inventoryRecord.Inventory_Id__c != null) {
                    recordsWithExternalId.add(inventoryRecord);
                } else {
                    recordsWithoutExternalId.add(inventoryRecord);
                }
            }
            upsert recordsWithExternalId Inventory_Id__c;
            insert recordsWithoutExternalId;

            Set<Id> inventoryIds = new Set<Id>();
            for (Inventory__c inventoryRecord : inventoryRecords) {
                if (inventoryRecord.Id != null) {
                    inventoryIds.add(inventoryRecord.Id);
                }
            }

            Map<Id, SObject> existingEventByInventoryId = getSingleRelatedByInventoryId(
                [
                    SELECT Id, Inventory__c
                    FROM Inventory_Event__c
                    WHERE Inventory__c IN :inventoryIds
                ]
            );
            Map<Id, SObject> existingMembershipByInventoryId = getSingleRelatedByInventoryId(
                [
                    SELECT Id, Inventory__c
                    FROM Membership__c
                    WHERE Inventory__c IN :inventoryIds
                ]
            );
            Map<Id, SObject> existingPackByInventoryId = getSingleRelatedByInventoryId(
                [
                    SELECT Id, Inventory__c
                    FROM Pack__c
                    WHERE Inventory__c IN :inventoryIds
                ]
            );
            Map<Id, SObject> existingSeasonTicketByInventoryId = getSingleRelatedByInventoryId(
                [
                    SELECT Id, Inventory__c
                    FROM Season_Ticket__c
                    WHERE Inventory__c IN :inventoryIds
                ]
            );

            List<Inventory_Event__c> eventRecords = new List<Inventory_Event__c>();
            List<Membership__c> membershipRecords = new List<Membership__c>();
            List<Pack__c> packRecords = new List<Pack__c>();
            List<Season_Ticket__c> seasonTicketRecords = new List<Season_Ticket__c>();
            Set<Id> desiredEventInventoryIds = new Set<Id>();
            Set<Id> desiredMembershipInventoryIds = new Set<Id>();
            Set<Id> desiredPackInventoryIds = new Set<Id>();
            Set<Id> desiredSeasonTicketInventoryIds = new Set<Id>();

            for (Integer i = 0; i < products.size(); i++) {
                Inventory__c inventoryRecord = inventoryRecords[i];

                Inventory_Event__c eventRecord = buildInventoryEventRecord(
                    products[i],
                    inventoryRecord,
                    (Inventory_Event__c) existingEventByInventoryId.get(inventoryRecord.Id)
                );
                if (eventRecord != null) {
                    eventRecords.add(eventRecord);
                    desiredEventInventoryIds.add(inventoryRecord.Id);
                }

                Membership__c membershipRecord = buildMembershipRecord(
                    products[i],
                    inventoryRecord,
                    (Membership__c) existingMembershipByInventoryId.get(inventoryRecord.Id)
                );
                if (membershipRecord != null) {
                    membershipRecords.add(membershipRecord);
                    desiredMembershipInventoryIds.add(inventoryRecord.Id);
                }

                Pack__c packRecord = buildPackRecord(
                    products[i],
                    inventoryRecord,
                    (Pack__c) existingPackByInventoryId.get(inventoryRecord.Id)
                );
                if (packRecord != null) {
                    packRecords.add(packRecord);
                    desiredPackInventoryIds.add(inventoryRecord.Id);
                }

                Season_Ticket__c seasonTicketRecord = buildSeasonTicketRecord(
                    products[i],
                    inventoryRecord,
                    (Season_Ticket__c) existingSeasonTicketByInventoryId.get(inventoryRecord.Id)
                );
                if (seasonTicketRecord != null) {
                    seasonTicketRecords.add(seasonTicketRecord);
                    desiredSeasonTicketInventoryIds.add(inventoryRecord.Id);
                }
            }

            upsert eventRecords;
            upsert membershipRecords;
            upsert packRecords;
            upsert seasonTicketRecords;

            List<Performance__c> existingPerformancesToDelete = new List<Performance__c>();
            Set<Id> eventIdsForPerformanceRefresh = new Set<Id>();
            for (Id inventoryId : desiredEventInventoryIds) {
                Inventory_Event__c existingEventRecord = (Inventory_Event__c) existingEventByInventoryId.get(inventoryId);
                if (existingEventRecord != null) {
                    eventIdsForPerformanceRefresh.add(existingEventRecord.Id);
                }
            }

            if (!eventIdsForPerformanceRefresh.isEmpty()) {
                existingPerformancesToDelete = [
                    SELECT Id
                    FROM Performance__c
                    WHERE Inventory_Event__c IN :eventIdsForPerformanceRefresh
                ];
            }

            if (!existingPerformancesToDelete.isEmpty()) {
                delete existingPerformancesToDelete;
            }

            deleteUndesiredRelatedRecords(existingEventByInventoryId, desiredEventInventoryIds, inventoryIds);
            deleteUndesiredRelatedRecords(existingMembershipByInventoryId, desiredMembershipInventoryIds, inventoryIds);
            deleteUndesiredRelatedRecords(existingPackByInventoryId, desiredPackInventoryIds, inventoryIds);
            deleteUndesiredRelatedRecords(existingSeasonTicketByInventoryId, desiredSeasonTicketInventoryIds, inventoryIds);

            List<Performance__c> performanceRecords = new List<Performance__c>();
            Map<Id, Inventory_Event__c> eventByInventoryId = new Map<Id, Inventory_Event__c>();
            for (Inventory_Event__c eventRecord : eventRecords) {
                eventByInventoryId.put((Id) eventRecord.get('Inventory__c'), eventRecord);
            }

            for (Integer i = 0; i < products.size(); i++) {
                Inventory_Event__c eventRecord = eventByInventoryId.get(inventoryRecords[i].Id);
                if (eventRecord != null) {
                    performanceRecords.addAll(buildPerformanceRecords(products[i], eventRecord));
                }
            }

            if (!performanceRecords.isEmpty()) {
                insert performanceRecords;
            }

            List<String> recordIds = new List<String>();
            for (Inventory__c recordItem : inventoryRecords) {
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

    // The middleware sometimes repeats the same product inside one request body;
    // keep only the last occurrence per external id so one call cannot insert twins.
    private static List<InventoryWrapper> dedupePayloadsById(List<InventoryWrapper> payloads) {
        Map<String, Integer> indexByExternalId = new Map<String, Integer>();
        List<InventoryWrapper> deduped = new List<InventoryWrapper>();
        for (InventoryWrapper inventoryWrapper : payloads) {
            String externalId = (inventoryWrapper == null || inventoryWrapper.id == null)
                ? null
                : String.valueOf(inventoryWrapper.id);
            if (externalId == null) {
                deduped.add(inventoryWrapper);
                continue;
            }
            Integer existingIndex = indexByExternalId.get(externalId);
            if (existingIndex != null) {
                deduped[existingIndex] = inventoryWrapper;
            } else {
                indexByExternalId.put(externalId, deduped.size());
                deduped.add(inventoryWrapper);
            }
        }
        return deduped;
    }

    private static InventoryWrapper buildWrapper(Object rawPayload) {
        return new InventoryWrapperFactory().build(rawPayload);
    }

    private static InventoryWrapper buildInventoryWrapper(Map<String, Object> rawPayload) {
        return new InventoryWrapperFactory().build(rawPayload);
    }

    private static void validatePayload(InventoryWrapper inventoryWrapper) {
        if (inventoryWrapper == null) {
            throw new InventoryWebhookException('Each inventory payload must be a valid JSON object.');
        }
    }

    private static Inventory__c buildInventoryRecord(InventoryWrapper inventoryWrapper) {
        // No pre-query matching: the upsert on the unique Inventory_Id__c external id
        // finds the existing record atomically, which a SELECT-then-upsert cannot.
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
        setCustomField(recordItem, 'Season_Id__c', inventoryWrapper.seasonId);
        setCustomField(recordItem, 'Contact_Product_Links__c', serializeRawValue(inventoryWrapper.contactProductLinks, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Granted_To_Tour_Promoter__c', inventoryWrapper.grantedToTourPromoter);
        setCustomField(recordItem, 'Exchangeable__c', inventoryWrapper.exchangeable);
        setCustomField(recordItem, 'Xlarge_Image_Url__c', truncateValue(inventoryWrapper.xlargeImageUrl, 255));
        setCustomField(recordItem, 'Additional_Partner_Contact_Number__c', truncateValue(inventoryWrapper.additionalPartnerContactNumber, 80));
        setCustomField(recordItem, 'Invoice_Partner_Contact_Number__c', truncateValue(inventoryWrapper.invoicePartnerContactNumber, 80));
        setCustomField(recordItem, 'Additional_State__c', truncateValue(inventoryWrapper.additionalState, 80));
        setCustomField(recordItem, 'Remark__c', truncateValue(inventoryWrapper.remark, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Ticket_Transfer_Limit__c', inventoryWrapper.ticketTransferLimit);
        setCustomField(recordItem, 'Redemption_Period__c', serializeRawValue(inventoryWrapper.redemptionPeriod, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Redemption_Products__c', serializeRawValue(inventoryWrapper.redemptionProducts, MAX_LONG_TEXT_LENGTH));
        setCustomField(recordItem, 'Sub_Topics__c', serializeRawValue(inventoryWrapper.subTopics, MAX_LONG_TEXT_LENGTH));

        return recordItem;
    }

    private static Inventory_Event__c buildInventoryEventRecord(
        InventoryWrapper inventoryWrapper,
        Inventory__c inventoryRecord,
        Inventory_Event__c existingEventRecord
    ) {
        return new InventoryEventBuilder().build(inventoryWrapper, inventoryRecord, existingEventRecord);
    }

    private static Membership__c buildMembershipRecord(
        InventoryWrapper inventoryWrapper,
        Inventory__c inventoryRecord,
        Membership__c existingMembershipRecord
    ) {
        return new MembershipBuilder().build(inventoryWrapper, inventoryRecord, existingMembershipRecord);
    }

    private static Pack__c buildPackRecord(
        InventoryWrapper inventoryWrapper,
        Inventory__c inventoryRecord,
        Pack__c existingPackRecord
    ) {
        return new PackBuilder().build(inventoryWrapper, inventoryRecord, existingPackRecord);
    }

    private static Season_Ticket__c buildSeasonTicketRecord(
        InventoryWrapper inventoryWrapper,
        Inventory__c inventoryRecord,
        Season_Ticket__c existingSeasonTicketRecord
    ) {
        return new SeasonTicketBuilder().build(inventoryWrapper, inventoryRecord, existingSeasonTicketRecord);
    }

    private static List<Performance__c> buildPerformanceRecords(InventoryWrapper inventoryWrapper, Inventory_Event__c eventRecord) {
        List<Performance__c> performanceRecords = new List<Performance__c>();
        if (
            inventoryWrapper == null ||
            eventRecord == null ||
            !(inventoryWrapper.event instanceof Map<String, Object>)
        ) {
            return performanceRecords;
        }

        Object performancesRaw = ((Map<String, Object>) inventoryWrapper.event).get('performances');
        if (!(performancesRaw instanceof List<Object>)) {
            return performanceRecords;
        }

        for (Object item : (List<Object>) performancesRaw) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }

            performanceRecords.add(buildPerformanceRecord((Map<String, Object>) item, eventRecord));
        }

        return performanceRecords;
    }

    private static Performance__c buildPerformanceRecord(Map<String, Object> performancePayload, Inventory_Event__c eventRecord) {
        Performance__c performanceRecord = new Performance__c(
            Name = buildPerformanceName(performancePayload)
        );

        setCustomField(performanceRecord, 'Inventory_Event__c', eventRecord.Id);
        setCustomField(performanceRecord, 'Performance_Id__c', asDecimal(performancePayload.get('id')));
        setCustomField(performanceRecord, 'Code__c', asString(performancePayload.get('code')));
        setCustomField(performanceRecord, 'Physical_Configuration_Id__c', asDecimal(performancePayload.get('physicalConfigurationId')));
        setCustomField(performanceRecord, 'Logical_Configuration_Id__c', asDecimal(performancePayload.get('logicalConfigurationId')));
        setCustomField(performanceRecord, 'Sale_Configuration_Id__c', asDecimal(performancePayload.get('saleConfigurationId')));
        setCustomField(performanceRecord, 'Rate_Type_Id__c', asDecimal(performancePayload.get('rateTypeId')));
        setCustomField(performanceRecord, 'Rate_Type_Code__c', asString(performancePayload.get('rateTypeCode')));
        setCustomField(performanceRecord, 'Rates_Table_Id__c', asDecimal(performancePayload.get('ratesTableId')));
        setCustomField(performanceRecord, 'Charges_Table_Id__c', asDecimal(performancePayload.get('chargesTableId')));
        setCustomField(performanceRecord, 'Start__c', asDatetime(performancePayload.get('start')));
        setCustomField(performanceRecord, 'Duration__c', asDecimal(performancePayload.get('duration')));
        setCustomField(performanceRecord, 'Space_Id__c', asDecimal(performancePayload.get('spaceId')));
        setCustomField(performanceRecord, 'Space_Code__c', asString(performancePayload.get('spaceCode')));
        setCustomField(performanceRecord, 'Site_Code__c', asString(performancePayload.get('siteCode')));
        setCustomField(performanceRecord, 'Kind__c', asString(performancePayload.get('kind')));
        setCustomField(performanceRecord, 'Kind_External_Name__c', asString(performancePayload.get('kindExternalName')));
        setCustomField(performanceRecord, 'Seat_Selection_Mode__c', asString(performancePayload.get('seatSelectionMode')));
        setCustomField(performanceRecord, 'Breaks_Quantity__c', asDecimal(performancePayload.get('breaksQuantity')));
        setCustomField(performanceRecord, 'State__c', asString(performancePayload.get('state')));
        setCustomField(performanceRecord, 'Image__c', asString(performancePayload.get('image')));
        setCustomField(performanceRecord, 'Venue_Image__c', asString(performancePayload.get('venueImage')));
        setCustomField(performanceRecord, 'Logo__c', asString(performancePayload.get('logo')));
        setCustomField(performanceRecord, 'Logo_Image__c', asString(performancePayload.get('logoImage')));
        setCustomField(performanceRecord, 'Force_Nominative_Tickets__c', asBoolean(performancePayload.get('forceNominativeTickets')));
        setCustomField(performanceRecord, 'Titling__c', asString(performancePayload.get('titling')));
        setCustomField(performanceRecord, 'Block_Comparison_Enabled__c', asBoolean(performancePayload.get('blockComparisonEnabled')));
        setCustomField(performanceRecord, 'Numbered__c', asBoolean(performancePayload.get('numbered')));
        setCustomField(performanceRecord, 'Always_Allow_Isolated_Seats__c', asBoolean(performancePayload.get('alwaysAllowIsolatedSeats')));
        setCustomField(performanceRecord, 'External_Name__c', serializeRawValue(performancePayload.get('externalName'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Internal_Name__c', serializeRawValue(performancePayload.get('internalName'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'External_Short_Name__c', serializeRawValue(performancePayload.get('externalShortName'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Name_Add_On__c', serializeRawValue(performancePayload.get('nameAddOn'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Space_External_Name__c', asString(performancePayload.get('spaceExternalName')));
        setCustomField(performanceRecord, 'Site_External_Name__c', asString(performancePayload.get('siteExternalName')));
        setCustomField(performanceRecord, 'Location__c', serializeRawValue(performancePayload.get('location'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Match__c', serializeRawValue(performancePayload.get('match'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Event_External_Name__c', asString(performancePayload.get('eventExternalName')));
        setCustomField(performanceRecord, 'External_Description__c', serializeRawValue(performancePayload.get('externalDescription'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Internal_Description__c', serializeRawValue(performancePayload.get('internalDescription'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Sale_Close_Exceptions__c', serializeRawValue(performancePayload.get('saleCloseExceptions'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Seat_Categories__c', serializeRawValue(performancePayload.get('seatCategories'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Prices__c', serializeRawValue(performancePayload.get('prices'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Charges__c', serializeRawValue(performancePayload.get('charges'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Comfort_Variable_Values__c', serializeRawValue(performancePayload.get('comfortVariableValues'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Performance_Type__c', asString(performancePayload.get('performanceType')));
        setCustomField(performanceRecord, 'Visit_Language_Code__c', asString(performancePayload.get('visitLanguageCode')));
        setCustomField(performanceRecord, 'Max_Seats_Per_Order__c', asDecimal(performancePayload.get('maxSeatsPerOrder')));
        setCustomField(performanceRecord, 'Item_Ids__c', serializeRawValue(performancePayload.get('itemIds'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Performance_Social_Network_Links__c', serializeRawValue(performancePayload.get('performanceSocialNetworkLinks'), MAX_LONG_TEXT_LENGTH));
        setCustomField(performanceRecord, 'Sale_Periods__c', serializeRawValue(performancePayload.get('salePeriods'), MAX_LONG_TEXT_LENGTH));
        return performanceRecord;
    }

    private static Map<Id, SObject> getSingleRelatedByInventoryId(List<SObject> records) {
        Map<Id, SObject> recordsByInventoryId = new Map<Id, SObject>();
        for (SObject recordItem : records) {
            Id inventoryId = (Id) recordItem.get('Inventory__c');
            if (inventoryId != null && !recordsByInventoryId.containsKey(inventoryId)) {
                recordsByInventoryId.put(inventoryId, recordItem);
            }
        }
        return recordsByInventoryId;
    }

    private static void deleteUndesiredRelatedRecords(
        Map<Id, SObject> existingRecordsByInventoryId,
        Set<Id> desiredInventoryIds,
        Set<Id> processedInventoryIds
    ) {
        List<SObject> recordsToDelete = new List<SObject>();
        for (Id inventoryId : processedInventoryIds) {
            if (desiredInventoryIds.contains(inventoryId)) {
                continue;
            }

            SObject existingRecord = existingRecordsByInventoryId.get(inventoryId);
            if (existingRecord != null) {
                recordsToDelete.add(existingRecord);
            }
        }

        if (!recordsToDelete.isEmpty()) {
            delete recordsToDelete;
        }
    }

    private static String buildRecordName(InventoryWrapper inventoryWrapper) {
        String italianInternalName = extractTranslatedValue(inventoryWrapper == null ? null : inventoryWrapper.internalName, 'it');
        if (!String.isBlank(italianInternalName)) {
            return italianInternalName.left(80);
        }

        String englishInternalName = extractTranslatedValue(inventoryWrapper == null ? null : inventoryWrapper.internalName, 'en');
        if (!String.isBlank(englishInternalName)) {
            return englishInternalName.left(80);
        }

        if (!String.isBlank(inventoryWrapper.code)) {
            return inventoryWrapper.code.left(80);
        }

        if (inventoryWrapper.id != null) {
            return ('Inventory ' + String.valueOf(inventoryWrapper.id)).left(80);
        }

        return 'Inventory';
    }

    private static String buildInventoryEventName(Map<String, Object> eventPayload) {
        if (eventPayload == null) {
            return 'Inventory Event';
        }

        String italianActivityName = extractTranslatedValue(eventPayload.get('activityExternalName'), 'it');
        if (!String.isBlank(italianActivityName)) {
            return italianActivityName.left(80);
        }

        String englishActivityName = extractTranslatedValue(eventPayload.get('activityExternalName'), 'en');
        if (!String.isBlank(englishActivityName)) {
            return englishActivityName.left(80);
        }

        Decimal activityId = asDecimal(eventPayload.get('activityId'));
        if (activityId != null) {
            return String.valueOf(activityId).left(80);
        }

        return 'Inventory Event';
    }

    private static String buildRelatedRecordName(Inventory__c inventoryRecord, String suffix) {
        String inventoryName = inventoryRecord == null ? null : inventoryRecord.Name;
        if (String.isBlank(inventoryName)) {
            inventoryName = 'Inventory';
        }

        if (String.isBlank(suffix)) {
            return inventoryName.left(80);
        }

        return (inventoryName + ' - ' + suffix).left(80);
    }

    private static Boolean isSimpleTicketSubtype(String productFamilySubType) {
        if (String.isBlank(productFamilySubType)) {
            return false;
        }

        String normalizedSubtype = productFamilySubType.replace('_', '').replace(' ', '').toUpperCase();
        String normalizedSimpleTicket = SIMPLE_TICKET_SUBTYPE.replace('_', '').toUpperCase();
        return normalizedSubtype == normalizedSimpleTicket;
    }

    private static String buildPerformanceName(Map<String, Object> performancePayload) {
        if (performancePayload == null) {
            return 'Performance';
        }

        String italianInternalName = extractTranslatedValue(performancePayload.get('internalName'), 'it');
        if (!String.isBlank(italianInternalName)) {
            return italianInternalName.left(80);
        }

        String englishInternalName = extractTranslatedValue(performancePayload.get('internalName'), 'en');
        if (!String.isBlank(englishInternalName)) {
            return englishInternalName.left(80);
        }

        String italianExternalName = extractTranslatedValue(performancePayload.get('externalName'), 'it');
        if (!String.isBlank(italianExternalName)) {
            return italianExternalName.left(80);
        }

        String englishExternalName = extractTranslatedValue(performancePayload.get('externalName'), 'en');
        if (!String.isBlank(englishExternalName)) {
            return englishExternalName.left(80);
        }

        String code = asString(performancePayload.get('code'));
        if (!String.isBlank(code)) {
            return code.left(80);
        }

        Decimal performanceId = asDecimal(performancePayload.get('id'));
        if (performanceId != null) {
            return String.valueOf(performanceId).left(80);
        }

        return 'Performance';
    }

    private static String extractTranslatedValue(Object rawValue, String preferredLocale) {
        if (!(rawValue instanceof Map<String, Object>) || String.isBlank(preferredLocale)) {
            return null;
        }

        Object translationsRaw = ((Map<String, Object>) rawValue).get('translations');
        if (!(translationsRaw instanceof List<Object>)) {
            return null;
        }

        for (Object item : (List<Object>) translationsRaw) {
            if (!(item instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> translation = (Map<String, Object>) item;
            String locale = asString(translation.get('locale'));
            String value = asString(translation.get('value'));
            if (preferredLocale.equalsIgnoreCase(locale) && !String.isBlank(value)) {
                return value;
            }
        }

        return null;
    }

    private static void setCustomField(SObject recordItem, String fieldApiName, Object value) {
        if (recordItem == null || String.isBlank(fieldApiName)) {
            return;
        }

        Map<String, SObjectField> fieldMap = recordItem.getSObjectType().getDescribe().fields.getMap();
        if (fieldMap.containsKey(fieldApiName)) {
            if (value == null) {
                // Checkbox fields reject null: coerce to false so an omitted
                // boolean in the payload does not fail the whole upsert.
                if (fieldMap.get(fieldApiName).getDescribe().getType() == DisplayType.Boolean) {
                    recordItem.put(fieldApiName, false);
                } else {
                    recordItem.put(fieldApiName, null);
                }
                return;
            }

            DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();
            Object coercedValue = coerceFieldValue(fieldDescribe, value);
            if (coercedValue != null || value == null) {
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

    private static Date asDate(Object value) {
        if (value == null) {
            return null;
        }

        if (value instanceof Date) {
            return (Date) value;
        }

        String stringValue = asString(value);
        if (String.isBlank(stringValue) || stringValue.length() < 10) {
            return null;
        }

        try {
            return Date.valueOf(stringValue.substring(0, 10));
        } catch (Exception e) {
            return null;
        }
    }

    private static Datetime asDatetime(Object value) {
        if (value == null) {
            return null;
        }

        if (value instanceof Datetime) {
            return (Datetime) value;
        }

        Long epochMillis = asLong(value);
        if (epochMillis != null) {
            try {
                return Datetime.newInstanceGmt(1970, 1, 1, 0, 0, 0).addSeconds(Integer.valueOf(String.valueOf(epochMillis / 1000)));
            } catch (Exception e) {
                return null;
            }
        }

        String stringValue = asString(value);
        if (String.isBlank(stringValue) || stringValue.length() < 19) {
            return null;
        }

        try {
            return Datetime.valueOf(stringValue.substring(0, 19).replace('T', ' '));
        } catch (Exception e) {
            return null;
        }
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

    private class InventoryWrapperFactory {
        private InventoryWrapper build(Object rawPayload) {
            if (!(rawPayload instanceof Map<String, Object>)) {
                throw new InventoryWebhookException('Each inventory payload must be a valid JSON object.');
            }

            return build((Map<String, Object>) rawPayload);
        }

        private InventoryWrapper build(Map<String, Object> rawPayload) {
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
            inventoryWrapper.seasonId = asLong(rawPayload.get('seasonId'));
            inventoryWrapper.contactProductLinks = rawPayload.get('contactProductLinks');
            inventoryWrapper.grantedToTourPromoter = asBoolean(rawPayload.get('grantedToTourPromoter'));
            inventoryWrapper.exchangeable = asBoolean(rawPayload.get('exchangeable'));
            inventoryWrapper.xlargeImageUrl = asString(rawPayload.get('xlargeImageUrl'));
            inventoryWrapper.additionalPartnerContactNumber = asString(rawPayload.get('additionalPartnerContactNumber'));
            inventoryWrapper.invoicePartnerContactNumber = asString(rawPayload.get('invoicePartnerContactNumber'));
            inventoryWrapper.additionalState = asString(rawPayload.get('additionalState'));
            inventoryWrapper.remark = asString(rawPayload.get('remark'));
            inventoryWrapper.ticketTransferLimit = asDecimal(rawPayload.get('ticketTransferLimit'));
            inventoryWrapper.redemptionPeriod = rawPayload.get('redemptionPeriod');
            inventoryWrapper.redemptionProducts = rawPayload.get('redemptionProducts');
            inventoryWrapper.subTopics = rawPayload.get('subTopics');
            return inventoryWrapper;
        }
    }

    private class InventoryEventBuilder {
        private Inventory_Event__c build(
            InventoryWrapper inventoryWrapper,
            Inventory__c inventoryRecord,
            Inventory_Event__c existingEventRecord
        ) {
            if (
                inventoryWrapper == null ||
                inventoryRecord == null ||
                !isSimpleTicketSubtype(inventoryWrapper.productFamilySubType) ||
                !(inventoryWrapper.event instanceof Map<String, Object>)
            ) {
                return null;
            }

            Map<String, Object> eventPayload = (Map<String, Object>) inventoryWrapper.event;
            Inventory_Event__c eventRecord = new Inventory_Event__c(
                Name = buildInventoryEventName(eventPayload)
            );
            if (existingEventRecord != null) {
                eventRecord.Id = existingEventRecord.Id;
            }

            setCustomField(eventRecord, 'Inventory__c', inventoryRecord.Id);
            setCustomField(eventRecord, 'Activity_Id__c', asDecimal(eventPayload.get('activityId')));
            setCustomField(eventRecord, 'Activity_Code__c', asString(eventPayload.get('activityCode')));
            setCustomField(eventRecord, 'Activity_Type__c', asString(eventPayload.get('activityType')));
            setCustomField(eventRecord, 'Time_Tolerance__c', asDecimal(eventPayload.get('timeTolerance')));
            setCustomField(eventRecord, 'Minimum_Age__c', asDecimal(eventPayload.get('minimumAge')));
            setCustomField(eventRecord, 'Language__c', asString(eventPayload.get('language')));
            setCustomField(eventRecord, 'Name_Add_On__c', serializeRawValue(eventPayload.get('nameAddOn'), MAX_LONG_TEXT_LENGTH));
            setCustomField(eventRecord, 'Activity_External_Name__c', serializeRawValue(eventPayload.get('activityExternalName'), MAX_LONG_TEXT_LENGTH));
            setCustomField(eventRecord, 'Competition_Type_Id__c', asDecimal(eventPayload.get('competitionTypeId')));
            setCustomField(eventRecord, 'Alert_Ratio__c', asDecimal(eventPayload.get('alertRatio')));
            setCustomField(eventRecord, 'Performances__c', serializeRawValue(eventPayload.get('performances'), MAX_LONG_TEXT_LENGTH));

            return eventRecord;
        }
    }

    private class MembershipBuilder {
        private Membership__c build(
            InventoryWrapper inventoryWrapper,
            Inventory__c inventoryRecord,
            Membership__c existingMembershipRecord
        ) {
            if (
                inventoryWrapper == null ||
                inventoryRecord == null ||
                !(inventoryWrapper.membership instanceof Map<String, Object>)
            ) {
                return null;
            }

            Map<String, Object> membershipPayload = (Map<String, Object>) inventoryWrapper.membership;
            Membership__c membershipRecord = new Membership__c(
                Name = buildRelatedRecordName(inventoryRecord, 'Membership')
            );
            if (existingMembershipRecord != null) {
                membershipRecord.Id = existingMembershipRecord.Id;
            }

            setCustomField(membershipRecord, 'Inventory__c', inventoryRecord.Id);
            setCustomField(membershipRecord, 'User_Define_Start_Validity__c', asBoolean(membershipPayload.get('userDefineStartValidity')));
            setCustomField(membershipRecord, 'Validity_Duration_Unit__c', asString(membershipPayload.get('validityDurationUnit')));
            setCustomField(membershipRecord, 'Validity_Duration__c', asDecimal(membershipPayload.get('validityDuration')));
            setCustomField(membershipRecord, 'Validity_End_Date__c', asDate(membershipPayload.get('validityEndDate')));
            setCustomField(membershipRecord, 'Validity_Start_Date__c', asDate(membershipPayload.get('validityStartDate')));
            setCustomField(membershipRecord, 'Validity_Rule__c', asString(membershipPayload.get('validityRule')));
            setCustomField(membershipRecord, 'Items__c', serializeRawValue(membershipPayload.get('items'), MAX_LONG_TEXT_LENGTH));

            return membershipRecord;
        }
    }

    private class PackBuilder {
        private Pack__c build(
            InventoryWrapper inventoryWrapper,
            Inventory__c inventoryRecord,
            Pack__c existingPackRecord
        ) {
            if (
                inventoryWrapper == null ||
                inventoryRecord == null ||
                !(inventoryWrapper.pack instanceof Map<String, Object>)
            ) {
                return null;
            }

            Map<String, Object> packPayload = (Map<String, Object>) inventoryWrapper.pack;
            Pack__c packRecord = new Pack__c(
                Name = buildRelatedRecordName(inventoryRecord, 'Pack')
            );
            if (existingPackRecord != null) {
                packRecord.Id = existingPackRecord.Id;
            }

            setCustomField(packRecord, 'Inventory__c', inventoryRecord.Id);
            setCustomField(packRecord, 'Ticket_Printing_Mode__c', asString(packPayload.get('ticketPrintingMode')));
            setCustomField(packRecord, 'Linked_Audience_Sub_Category_Ids__c', serializeRawValue(packPayload.get('linkedAudienceSubCategoryIds'), MAX_LONG_TEXT_LENGTH));
            setCustomField(packRecord, 'Package_Lines__c', serializeRawValue(packPayload.get('packageLine'), MAX_LONG_TEXT_LENGTH));

            return packRecord;
        }
    }

    private class SeasonTicketBuilder {
        private Season_Ticket__c build(
            InventoryWrapper inventoryWrapper,
            Inventory__c inventoryRecord,
            Season_Ticket__c existingSeasonTicketRecord
        ) {
            if (
                inventoryWrapper == null ||
                inventoryRecord == null ||
                !(inventoryWrapper.seasonTicket instanceof Map<String, Object>)
            ) {
                return null;
            }

            Map<String, Object> seasonTicketPayload = (Map<String, Object>) inventoryWrapper.seasonTicket;
            Season_Ticket__c seasonTicketRecord = new Season_Ticket__c(
                Name = buildRelatedRecordName(inventoryRecord, 'Season Ticket')
            );
            if (existingSeasonTicketRecord != null) {
                seasonTicketRecord.Id = existingSeasonTicketRecord.Id;
            }

            setCustomField(seasonTicketRecord, 'Inventory__c', inventoryRecord.Id);
            setCustomField(seasonTicketRecord, 'Championship_Season_Ticket__c', asBoolean(seasonTicketPayload.get('championshipSeasonTicket')));
            setCustomField(seasonTicketRecord, 'Fixed_Seat__c', asBoolean(seasonTicketPayload.get('fixedSeat')));
            setCustomField(seasonTicketRecord, 'Ticket_Printing_Mode__c', asString(seasonTicketPayload.get('ticketPrintingMode')));
            setCustomField(seasonTicketRecord, 'Season_Ticket_Subjects__c', serializeRawValue(seasonTicketPayload.get('seasonTicketSubjects'), MAX_LONG_TEXT_LENGTH));
            setCustomField(seasonTicketRecord, 'Season_Ticket_Lines__c', serializeRawValue(seasonTicketPayload.get('seasonTicketLines'), MAX_LONG_TEXT_LENGTH));

            return seasonTicketRecord;
        }
    }

    global class InventoryWebhookException extends Exception {
    }
}
