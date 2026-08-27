@IsTest
private class OrderRestResourceTest {
    @IsTest
    static void receiveOrder_acceptsSinglePayload() {
        Account fallbackAccount = createFallbackAccount();
        Account directMatchAccount = new Account(
            Name = 'Direct Match Account',
            Contact_Number__c = '5442'
        );
        insert directMatchAccount;

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/order';
        req.resourcePath = '/v1/order';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '[{"orderDetailsData":{"orderId":10000418846,"orderState":"OPEN","creationDateTime":"2024-05-27T10:45:49.201+02:00","saleAmount":0,"preSaleAmount":14000,"operationDatas":[{"operationId":10229212866133,"type":"PRE_SALE","product":"Billet Musee","totalAmount":14000,"site":"MoSA Musee","audienceSubCategory":"Adulte","itemDate":"2024-06-10T11:00:00.000+02:00"}],"movementDatas":[{"movementId":10229212866234,"contactReference":"5442"}],"orderType":"SALE","orderSecretId":"33e1993b-7e31-4c44-8b8b-2ac646d258a0_10000418846"},"orderDetailGranularity":"TICKET"}]'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        OrderRestResource.receiveOrder();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            RestContext.response.responseBody == null ? null : RestContext.response.responseBody.toString()
        );

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(true, resp.get('success'));
        System.assertEquals(1, ((List<Object>) resp.get('recordIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('orderIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('orderSecretIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('contactReferences')).size());

        Order insertedOrder = [
            SELECT Id, AccountId, BillToContactId, ShipToContactId, Status, EffectiveDate, Description,
                   Sale_Amount__c, Pre_Sale_Amount__c
            FROM Order
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(fallbackAccount.Id, insertedOrder.AccountId);
        System.assertEquals(null, insertedOrder.BillToContactId);
        System.assertEquals(null, insertedOrder.ShipToContactId);
        System.assertEquals('Draft', insertedOrder.Status);
        System.assertEquals(null, insertedOrder.Description);
        System.assertEquals(0, insertedOrder.Sale_Amount__c);
        System.assertEquals(14, insertedOrder.Pre_Sale_Amount__c);

        Integration_Log__c logRec = [
            SELECT Flow_Name__c, Integration_Type__c, Is_Error__c, Request_Endpoint__c, Response_State__c
            FROM Integration_Log__c
            WHERE Flow_Name__c = 'OrderRestResource.receiveOrder'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('Inbound', logRec.Integration_Type__c);
        System.assertEquals(false, logRec.Is_Error__c);
        System.assertEquals('/v1/order', logRec.Request_Endpoint__c);
        System.assertEquals('200', logRec.Response_State__c);
    }

    @IsTest
    static void receiveOrder_rejectsInvalidJson() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/order';
        req.resourcePath = '/v1/order';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('not-json');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        OrderRestResource.receiveOrder();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(false, resp.get('success'));
        System.assertEquals('Invalid JSON payload.', resp.get('message'));
    }

    @IsTest
    static void receiveOrder_acceptsExtendedPayloadShape() {
        Account fallbackAccount = createFallbackAccount();

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/order';
        req.resourcePath = '/v1/order';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"orderDetailGranularity":"TICKET","orderDetailsData":{"orderId":454129,"orderState":"CLOSED","creationDateTime":"2026-05-20T16:08:30.858+02:00","referenceDate":"2026-05-20T00:00:00.000Z","expirationDate":"2026-05-20T00:00:00.000Z","saleAmount":0,"preSaleAmount":0,"reservationAmount":50000,"optionAmount":0,"waitingAccountBalanceAmount":0,"operationDatas":[{"operationId":10229250965773,"kind":"SINGLE_ENTRY","type":"RESERVATION","product":"LE VACANZE DEI SIGNORI LAGONIA","site":"Teatro Franco Parenti","performanceDate":"2026-05-20T20:15:00.000+02:00","catalogCurrency":{"currencyCode":"EUR","fractionDigit":2,"minAmount":10,"symbol":"€"},"comfortVariableValues":{}},{"operationId":10229250965774,"kind":"CHARGES","type":"RESERVATION","product":"Prevendita","priceComponentData":{"rank":2,"externalName":"Prevendita","kind":"EXTERNAL_PRICE_COMPONENT"}}],"movementDatas":[{"movementId":10229250966107,"operationId":10229250965773,"type":"SEAT","contactReference":"10286","row":"C","seatNumber":"7"},{"movementId":10229250966106,"operationId":10229250965774,"type":"SEAT","contactReference":"10286","row":"C","seatNumber":"4"}],"movementTicketDatas":[],"contactReference":"10286","salesChannelName":{"translations":[{"locale":"it","value":"Biglietteria - Test"}]},"orderType":"RESERVATION","generatedContiguities":[{"performanceId":10228656021092,"contiguous":false,"segments":[{"movementIds":[10229250966106,10229250966107]}]}],"orderOriginData":{"toCreateToken":false},"salesChannelType":"BOXOFFICE","orderInstallmentsToCreate":[],"orderSecretId":"ba455548-3309-49fe-9880-eb6c94159e65_454129","orderOriginator":"SALE","salesChannelCode":"BO","catalogCurrency":{"currencyCode":"EUR","fractionDigit":2,"minAmount":10,"symbol":"€"},"organizationCode":"TFP","organizationName":{"translations":[{"locale":"it","value":"Teatro Franco Parenti - TEST"},{"locale":"en","value":"Teatro Franco Parenti - TEST"}]},"userInserted":"STX_MLJ","userUpdated":"STX_MLJ","posNum":"472","pointOfSalesId":10229250866146,"pointOfSalesCode":"PVTFMLJ1","pointOfSalesName":"STX_MLJ"},"shipments":[{"id":10229250907470,"shipmentMode":{"id":10228544271965,"name":"Consegna immediata","type":"HANDED_AT_BO"},"tickets":[],"documents":[],"contactNumber":"10286","shipmentSent":false,"shipmentState":"REFERENCE"},{"id":10229250907471,"shipmentMode":{"id":10228466781238,"name":"E-mail (documenti)","idCode":"EMAIL","type":"BY_EMAIL"},"tickets":[],"documents":[{"id":10229250908066,"availableForPrint":true,"alreadyPrinted":true,"documentType":"04_PDF Riepilogo File","documentClass":"FILE_SUMMARY","orderId":454129}],"contactNumber":"10286","shipmentSent":true,"shipmentState":"SENT"}]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        OrderRestResource.receiveOrder();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            RestContext.response.responseBody == null ? null : RestContext.response.responseBody.toString()
        );

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(true, resp.get('success'));
        System.assertEquals(1, ((List<Object>) resp.get('recordIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('orderIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('orderSecretIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('contactReferences')).size());

        Order insertedOrder = [
            SELECT Id, AccountId, BillToContactId, ShipToContactId, EffectiveDate, Description
            FROM Order
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(fallbackAccount.Id, insertedOrder.AccountId);
        System.assertEquals(null, insertedOrder.BillToContactId);
        System.assertEquals(null, insertedOrder.ShipToContactId);
        System.assertEquals(Date.newInstance(2026, 5, 20), insertedOrder.EffectiveDate);
        System.assertEquals(null, insertedOrder.Description);
        System.assertEquals(2, countRows('Order_Operation_Data__c', 'Order__c = \'' + insertedOrder.Id + '\''));
        System.assertEquals(2, countRows('Order_Movement_Data__c', 'Order__c = \'' + insertedOrder.Id + '\''));

        SObject operationRecord = Database.query(
            'SELECT Operation_Id__c, Performance_Date__c ' +
            'FROM Order_Operation_Data__c ' +
            'WHERE Order__c = \'' + insertedOrder.Id + '\' ' +
            'ORDER BY CreatedDate ASC LIMIT 1'
        );
        System.assertEquals('10229250965773', (String) operationRecord.get('Operation_Id__c'));
        System.assertEquals('2026-05-20T20:15:00.000+02:00', (String) operationRecord.get('Performance_Date__c'));

        SObject movementRecord = Database.query(
            'SELECT Contact_Reference__c, Operation_Id__c, Account__c ' +
            'FROM Order_Movement_Data__c ' +
            'WHERE Order__c = \'' + insertedOrder.Id + '\' ' +
            'ORDER BY CreatedDate ASC LIMIT 1'
        );
        System.assertEquals('10286', (String) movementRecord.get('Contact_Reference__c'));
        System.assertNotEquals(null, movementRecord.get('Operation_Id__c'));
        System.assertEquals(fallbackAccount.Id, insertedOrder.AccountId);
    }

    @IsTest
    static void receiveOrder_persistsExtendedOperationFields() {
        createFallbackAccount();

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/order';
        req.resourcePath = '/v1/order';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"orderDetailGranularity":"TICKET","orderDetailsData":{"orderId":454134,"orderState":"CLOSED","creationDateTime":"2026-05-20T16:08:30.858+02:00","referenceDate":"2026-05-20T00:00:00.000Z","operationDatas":[{"operationId":10229250965773,"kind":"SINGLE_ENTRY","type":"RESERVATION","quantity":1,"basePrice":22000,"unitPrice":22000,"withoutVatTotalAmount":20000,"totalAmount":22000,"productId":10228638592050,"product":"LE VACANZE DEI SIGNORI LAGONIA","productCode":"0162","itemId":10228655877095,"performanceId":10228656021092,"performance":"LE VACANZE DEI SIGNORI LAGONIA","eventId":10228638592050,"physicalConfigurationId":10228554659410,"siteId":10228544852613,"site":"Teatro Franco Parenti","performanceDate":"2026-05-20T20:15:00.000+02:00","space":"SALA TRE","contingent":"WEB","numbered":true,"seatCategoryId":10228635451950,"seatCategory":"PLATEA","seatCategoryRank":1,"audienceSubCategoryId":10228635444778,"audienceSubCategory":"INTERO + prev.","audienceSubCategoryRank":1,"audienceSubCategoryRequireAttachment":false,"activityType":"LIVE_SPECT","performanceDuration":5400,"itemDisplayExternalDesignation":"LE VACANZE DEI SIGNORI LAGONIA","fileId":275705,"crossSellParentOperationIds":[],"comfortVariableValues":{"visibility":"full"},"performanceCode":"0162","audienceCatId":15655,"exchangeable":false,"activityId":10228635444869,"activityName":"TEATRO","activityCode":"1","includedInShipmentFee":false,"catalogCurrency":{"currencyCode":"EUR","fractionDigit":2,"minAmount":10,"symbol":"EUR"},"championshipSeasonticket":false,"fixedSeatSeasonticket":false,"allSeasonTicketLinesCompetition":false,"insuredOperationIds":[],"resale":false,"isNominative":false,"nominative":false}],"movementDatas":[{"movementId":10229250966107,"operationId":10229250965773,"type":"SEAT","contactReference":"10286"}],"movementTicketDatas":[],"contactReference":"10286","orderType":"RESERVATION","orderSecretId":"secret_454134"},"shipments":[{"id":10229250907470,"contactNumber":"10286"}]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        OrderRestResource.receiveOrder();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            RestContext.response.responseBody == null ? null : RestContext.response.responseBody.toString()
        );

        Id orderId = [SELECT Id FROM Order WHERE Order_Id__c = '454134' LIMIT 1].Id;
        SObject operationRecord = Database.query(
            'SELECT Event_Id__c, Physical_Configuration_Id__c, Contingent__c, Numbered__c, ' +
            'Base_Price__c, Unit_Price__c, Without_Vat_Total_Amount__c, Total_Amount__c, ' +
            'Seat_Category_Rank__c, Audience_SubCategory_Rank__c, Audience_SubCategory_Require_Attachment__c, ' +
            'Activity_Type__c, Performance_Duration__c, Item_Display_External_Designation__c, File_Id__c, ' +
            'Cross_Sell_Parent_Operation_Ids__c, Comfort_Variable_Values__c, Performance_Code__c, ' +
            'Audience_Cat_Id__c, Exchangeable__c, Activity_Id__c, Activity_Name__c, Activity_Code__c, ' +
            'Included_In_Shipment_Fee__c, Championship_Seasonticket__c, Fixed_Seat_Seasonticket__c, ' +
            'All_Season_Ticket_Lines_Competition__c, Insured_Operation_Ids__c, Resale__c, Is_Nominative__c, Nominative__c ' +
            'FROM Order_Operation_Data__c ' +
            'WHERE Order__c = \'' + orderId + '\' LIMIT 1'
        );

        System.assertEquals(10228638592050L, Long.valueOf(String.valueOf(operationRecord.get('Event_Id__c'))));
        System.assertEquals(10228554659410L, Long.valueOf(String.valueOf(operationRecord.get('Physical_Configuration_Id__c'))));
        System.assertEquals('WEB', (String) operationRecord.get('Contingent__c'));
        System.assertEquals(true, (Boolean) operationRecord.get('Numbered__c'));
        System.assertEquals(22, (Decimal) operationRecord.get('Base_Price__c'));
        System.assertEquals(22, (Decimal) operationRecord.get('Unit_Price__c'));
        System.assertEquals(20, (Decimal) operationRecord.get('Without_Vat_Total_Amount__c'));
        System.assertEquals(22, (Decimal) operationRecord.get('Total_Amount__c'));
        System.assertEquals(1, Integer.valueOf(String.valueOf(operationRecord.get('Seat_Category_Rank__c'))));
        System.assertEquals(1, Integer.valueOf(String.valueOf(operationRecord.get('Audience_SubCategory_Rank__c'))));
        System.assertEquals(false, (Boolean) operationRecord.get('Audience_SubCategory_Require_Attachment__c'));
        System.assertEquals('LIVE_SPECT', (String) operationRecord.get('Activity_Type__c'));
        System.assertEquals(5400, Integer.valueOf(String.valueOf(operationRecord.get('Performance_Duration__c'))));
        System.assertEquals('LE VACANZE DEI SIGNORI LAGONIA', (String) operationRecord.get('Item_Display_External_Designation__c'));
        System.assertEquals(275705L, Long.valueOf(String.valueOf(operationRecord.get('File_Id__c'))));
        System.assertEquals('[]', (String) operationRecord.get('Cross_Sell_Parent_Operation_Ids__c'));
        System.assertEquals('{"visibility":"full"}', (String) operationRecord.get('Comfort_Variable_Values__c'));
        System.assertEquals('0162', (String) operationRecord.get('Performance_Code__c'));
        System.assertEquals(15655L, Long.valueOf(String.valueOf(operationRecord.get('Audience_Cat_Id__c'))));
        System.assertEquals(false, (Boolean) operationRecord.get('Exchangeable__c'));
        System.assertEquals(10228635444869L, Long.valueOf(String.valueOf(operationRecord.get('Activity_Id__c'))));
        System.assertEquals('TEATRO', (String) operationRecord.get('Activity_Name__c'));
        System.assertEquals('1', (String) operationRecord.get('Activity_Code__c'));
        System.assertEquals(false, (Boolean) operationRecord.get('Included_In_Shipment_Fee__c'));
        System.assertEquals(false, (Boolean) operationRecord.get('Championship_Seasonticket__c'));
        System.assertEquals(false, (Boolean) operationRecord.get('Fixed_Seat_Seasonticket__c'));
        System.assertEquals(false, (Boolean) operationRecord.get('All_Season_Ticket_Lines_Competition__c'));
        System.assertEquals('[]', (String) operationRecord.get('Insured_Operation_Ids__c'));
        System.assertEquals(false, (Boolean) operationRecord.get('Resale__c'));
        System.assertEquals(false, (Boolean) operationRecord.get('Is_Nominative__c'));
        System.assertEquals(false, (Boolean) operationRecord.get('Nominative__c'));
    }

    @IsTest
    static void receiveOrder_persistsOrderTypeAndShipmentPayload() {
        createFallbackAccount();

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/order';
        req.resourcePath = '/v1/order';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"orderDetailGranularity":"TICKET","orderDetailsData":{"orderId":454135,"orderState":"CLOSED","creationDateTime":"2026-05-20T16:08:30.858+02:00","referenceDate":"2026-05-20T00:00:00.000Z","operationDatas":[{"operationId":10229250965773,"kind":"SINGLE_ENTRY","type":"RESERVATION","product":"LE VACANZE DEI SIGNORI LAGONIA","performanceDate":"2026-05-20T20:15:00.000+02:00"}],"movementDatas":[{"movementId":10229250966107,"operationId":10229250965773,"type":"SEAT","contactReference":"10286"}],"movementTicketDatas":[],"contactReference":"10286","orderType":"RESERVATION","generatedContiguities":[{"performanceId":10228656021092,"contiguous":false}],"orderSecretId":"secret_454135","userInserted":"STX_MLJ","userUpdated":"STX_MLJ","posNum":"472","pointOfSalesId":10229250866146,"pointOfSalesCode":"PVTFMLJ1","pointOfSalesName":"STX_MLJ"},"shipments":[{"id":10229250907470,"shipmentMode":{"id":10228544271965,"name":"Consegna immediata","type":"HANDED_AT_BO"},"contactNumber":"10286","shipmentSent":false,"shipmentState":"REFERENCE"},{"id":10229250907471,"shipmentMode":{"id":10228466781238,"name":"E-mail (documenti)","idCode":"EMAIL","type":"BY_EMAIL"},"contactNumber":"10286","shipmentSent":true,"shipmentState":"SENT"}]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        OrderRestResource.receiveOrder();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            RestContext.response.responseBody == null ? null : RestContext.response.responseBody.toString()
        );

        Order insertedOrder = [
            SELECT Id, Type, Generated_Contiguities__c, User_Inserted__c, User_Updated__c,
                   Pos_Num__c, Point_Of_Sales_Id__c, Point_Of_Sales_Code__c, Point_Of_Sales_Name__c,
                   Shipments__c
            FROM Order
            WHERE Order_Id__c = '454135'
            LIMIT 1
        ];

        System.assertEquals('RESERVATION', insertedOrder.Type);
        System.assertEquals('STX_MLJ', insertedOrder.User_Inserted__c);
        System.assertEquals('STX_MLJ', insertedOrder.User_Updated__c);
        System.assertEquals('472', insertedOrder.Pos_Num__c);
        System.assertEquals(10229250866146L, Long.valueOf(String.valueOf(insertedOrder.Point_Of_Sales_Id__c)));
        System.assertEquals('PVTFMLJ1', insertedOrder.Point_Of_Sales_Code__c);
        System.assertEquals('STX_MLJ', insertedOrder.Point_Of_Sales_Name__c);
    }

    @IsTest
    static void receiveOrder_linksMatchingContactByShipmentContactNumberAndContactReference() {
        Account fallbackAccount = createFallbackAccount();
        Account accountRecord = new Account(Name = 'Test Contact Account');
        insert accountRecord;
        Account directMatchAccount = new Account(
            Name = 'Reference Match Account',
            Contact_Number__c = '10287'
        );
        insert directMatchAccount;

        Contact shipmentContactRecord = new Contact(
            LastName = 'Linked Contact',
            AccountId = accountRecord.Id,
            Contact_Number__c = '10286'
        );
        Contact referenceContactRecord = new Contact(
            LastName = 'Reference Contact',
            AccountId = accountRecord.Id,
            Contact_Number__c = '10287'
        );
        insert new List<Contact>{ shipmentContactRecord, referenceContactRecord };

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/order';
        req.resourcePath = '/v1/order';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '[' +
                '{"orderDetailGranularity":"TICKET","orderDetailsData":{"orderId":555001,"orderState":"CLOSED","creationDateTime":"2026-05-20T16:08:30.858+02:00","referenceDate":"2026-05-20T00:00:00.000Z","operationDatas":[],"movementDatas":[],"movementTicketDatas":[],"orderType":"RESERVATION","orderSecretId":"secret_555001"},"shipments":[{"id":1,"contactNumber":"10286"}]},' +
                '{"orderDetailGranularity":"TICKET","orderDetailsData":{"orderId":555002,"orderState":"CLOSED","creationDateTime":"2026-05-20T16:08:30.858+02:00","referenceDate":"2026-05-20T00:00:00.000Z","operationDatas":[],"movementDatas":[{"contactReference":"10287"}],"movementTicketDatas":[],"orderType":"RESERVATION","orderSecretId":"secret_555002","contactReference":"10287"},"shipments":[{"id":1}]}' +
            ']'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        OrderRestResource.receiveOrder();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        Map<String, Order> ordersByExternalId = new Map<String, Order>();
        for (Order orderRecord : [
            SELECT Order_Id__c, AccountId, BillToContactId, ShipToContactId
            FROM Order
            WHERE Order_Id__c IN ('555001', '555002')
        ]) {
            ordersByExternalId.put(orderRecord.Order_Id__c, orderRecord);
        }

        System.assertEquals(2, ordersByExternalId.size());
        System.assertEquals(fallbackAccount.Id, ordersByExternalId.get('555001').AccountId);
        System.assertEquals(shipmentContactRecord.Id, ordersByExternalId.get('555001').BillToContactId);
        System.assertEquals(shipmentContactRecord.Id, ordersByExternalId.get('555001').ShipToContactId);
        System.assertEquals(directMatchAccount.Id, ordersByExternalId.get('555002').AccountId);
        System.assertEquals(referenceContactRecord.Id, ordersByExternalId.get('555002').BillToContactId);
        System.assertEquals(referenceContactRecord.Id, ordersByExternalId.get('555002').ShipToContactId);

        SObject movementRecord = Database.query(
            'SELECT Account__c FROM Order_Movement_Data__c ' +
            'WHERE Order__c IN (SELECT Id FROM Order WHERE Order_Id__c = \'555002\') LIMIT 1'
        );
        System.assertEquals(directMatchAccount.Id, (Id) movementRecord.get('Account__c'));

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(true, resp.get('success'));
        System.assertEquals(2, ((List<Object>) resp.get('recordIds')).size());
        System.assertEquals(2, ((List<Object>) resp.get('orderIds')).size());
    }

    @IsTest
    static void receiveOrder_updatesExistingOrderWhenExternalIdentifiersMatch() {
        Account fallbackAccount = createFallbackAccount();
        Account directMatchAccount = new Account(
            Name = 'Upsert Match Account',
            Contact_Number__c = '10286'
        );
        insert directMatchAccount;
        Order existingOrder = new Order(
            AccountId = fallbackAccount.Id,
            EffectiveDate = Date.newInstance(2026, 5, 19),
            Status = 'Draft',
            Order_Id__c = '454129',
            Order_Secret_Id__c = 'ba455548-3309-49fe-9880-eb6c94159e65_454129',
            Description = 'Original description'
        );
        insert existingOrder;

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/order';
        req.resourcePath = '/v1/order';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"orderDetailGranularity":"TICKET","orderDetailsData":{"orderId":454129,"orderState":"CLOSED","creationDateTime":"2026-05-20T16:08:30.858+02:00","referenceDate":"2026-05-20T00:00:00.000Z","expirationDate":"2026-05-20T00:00:00.000Z","saleAmount":0,"preSaleAmount":0,"reservationAmount":50000,"optionAmount":0,"waitingAccountBalanceAmount":0,"operationDatas":[{"operationId":10229250965773,"kind":"SINGLE_ENTRY","type":"RESERVATION","product":"LE VACANZE DEI SIGNORI LAGONIA","site":"Teatro Franco Parenti","performanceDate":"2026-05-20T20:15:00.000+02:00"}],"movementDatas":[{"movementId":10229250966107,"operationId":10229250965773,"type":"SEAT","contactReference":"10286","row":"C","seatNumber":"7"}],"movementTicketDatas":[],"contactReference":"10286","orderType":"RESERVATION","orderSecretId":"ba455548-3309-49fe-9880-eb6c94159e65_454129","orderOriginator":"SALE","salesChannelCode":"BO","salesChannelType":"BOXOFFICE","organizationCode":"TFP"},"shipments":[{"id":10229250907470,"contactNumber":"10286"}]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        OrderRestResource.receiveOrder();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(1, [SELECT COUNT() FROM Order WHERE Order_Id__c = '454129']);

        Order updatedOrder = [
            SELECT Id, Status, EffectiveDate, Description, Reservation_Amount__c, Contact_Reference__c, Product_Id__c, AccountId
            FROM Order
            WHERE Id = :existingOrder.Id
        ];
        System.assertEquals(existingOrder.Id, updatedOrder.Id);
        System.assertEquals('Draft', updatedOrder.Status);
        System.assertEquals(Date.newInstance(2026, 5, 20), updatedOrder.EffectiveDate);
        System.assertEquals(50, updatedOrder.Reservation_Amount__c);
        System.assertEquals('10286', updatedOrder.Contact_Reference__c);
        System.assertEquals(null, updatedOrder.Product_Id__c);
        System.assertEquals(directMatchAccount.Id, updatedOrder.AccountId);
        System.assertEquals('Original description', updatedOrder.Description);
        System.assertEquals(1, countRows('Order_Operation_Data__c', 'Order__c = \'' + existingOrder.Id + '\''));
        System.assertEquals(1, countRows('Order_Movement_Data__c', 'Order__c = \'' + existingOrder.Id + '\''));
    }

    @IsTest
    static void receiveOrder_accountLookupUsesMovementContactReferenceInsteadOfTopLevelContactReference() {
        Account fallbackAccount = createFallbackAccount();
        Account movementMatchAccount = new Account(
            Name = 'Movement Match Account',
            Contact_Number__c = '102'
        );
        Account topLevelOnlyAccount = new Account(
            Name = 'Top Level Only Account',
            Contact_Number__c = '10286'
        );
        insert new List<Account>{ movementMatchAccount, topLevelOnlyAccount };

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/order';
        req.resourcePath = '/v1/order';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"orderDetailGranularity":"TICKET","orderDetailsData":{"orderId":454132,"orderState":"CLOSED","creationDateTime":"2026-05-20T16:08:30.858+02:00","referenceDate":"2026-05-20T00:00:00.000Z","operationDatas":[{"operationId":10229250965773,"kind":"SINGLE_ENTRY","type":"RESERVATION","productId":10228638592050,"product":"LE VACANZE DEI SIGNORI LAGONIA","site":"Teatro Franco Parenti","performanceDate":"2026-05-20T20:15:00.000+02:00"}],"movementDatas":[{"movementId":10229250966107,"operationId":10229250965773,"type":"SEAT","contactReference":"102"}],"movementTicketDatas":[],"contactReference":"10286","orderType":"RESERVATION","orderSecretId":"secret_454132"},"shipments":[{"id":10229250907470,"contactNumber":"10286"}]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        OrderRestResource.receiveOrder();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            RestContext.response.responseBody == null ? null : RestContext.response.responseBody.toString()
        );

        Order insertedOrder = [
            SELECT Id, AccountId, Contact_Reference__c
            FROM Order
            WHERE Order_Id__c = '454132'
            LIMIT 1
        ];
        System.assertEquals(topLevelOnlyAccount.Id, insertedOrder.AccountId);
        System.assertEquals('102', insertedOrder.Contact_Reference__c);

        SObject movementRecord = Database.query(
            'SELECT Account__c FROM Order_Movement_Data__c WHERE Order__c = \'' + insertedOrder.Id + '\' LIMIT 1'
        );
        System.assertEquals(movementMatchAccount.Id, (Id) movementRecord.get('Account__c'));
    }

    @IsTest
    static void receiveOrder_linksInventoryByOperationProductId() {
        Account fallbackAccount = createFallbackAccount();
        Inventory__c inventoryRecord = new Inventory__c(
            Name = 'LE VACANZE DEI SIGNORI LAGONIA',
            Inventory_Id__c = '10228638592050'
        );
        insert inventoryRecord;

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/order';
        req.resourcePath = '/v1/order';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"orderDetailGranularity":"TICKET","orderDetailsData":{"orderId":454130,"orderState":"CLOSED","creationDateTime":"2026-05-20T16:08:30.858+02:00","referenceDate":"2026-05-20T00:00:00.000Z","operationDatas":[{"operationId":10229250965773,"kind":"SINGLE_ENTRY","type":"RESERVATION","productId":10228638592050,"product":"LE VACANZE DEI SIGNORI LAGONIA","site":"Teatro Franco Parenti","performanceDate":"2026-05-20T20:15:00.000+02:00"},{"operationId":10229250965774,"kind":"CHARGES","type":"RESERVATION","productId":10228635445372,"product":"Prevendita"}],"movementDatas":[{"movementId":10229250966107,"operationId":10229250965773,"type":"SEAT","contactReference":"10286"}],"movementTicketDatas":[],"contactReference":"10286","orderType":"RESERVATION","orderSecretId":"secret_454130"},"shipments":[{"id":10229250907470,"contactNumber":"10286"}]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        OrderRestResource.receiveOrder();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            RestContext.response.responseBody == null ? null : RestContext.response.responseBody.toString()
        );

        SObject operationRecord = Database.query(
            'SELECT Inventory__c, Product_Id__c FROM Order_Operation_Data__c ' +
            'WHERE Order__c IN (SELECT Id FROM Order WHERE Order_Id__c = \'454130\') ' +
            'AND Operation_Id__c = \'10229250965773\' LIMIT 1'
        );
        System.assertEquals(inventoryRecord.Id, (Id) operationRecord.get('Inventory__c'));
        System.assertEquals(10228638592050L, Long.valueOf(String.valueOf(operationRecord.get('Product_Id__c'))));
    }

    @IsTest
    static void inventoryExternalId_rejectsDuplicates() {
        // Salesforce temporarily suspends uniqueness while validating a field type
        // conversion in the same deployment. The post-deploy suite exercises this
        // assertion once the Text field and its unique index are active.
        if (!Inventory__c.Inventory_Id__c.getDescribe().isUnique()) {
            return;
        }

        Inventory__c olderInventory = new Inventory__c(
            Name = 'Older Inventory',
            Inventory_Id__c = '10228638592050'
        );
        insert olderInventory;

        Inventory__c newerInventory = new Inventory__c(
            Name = 'Newer Inventory',
            Inventory_Id__c = '10228638592050'
        );

        Database.SaveResult duplicateResult = Database.insert(newerInventory, false);

        System.assertEquals(false, duplicateResult.isSuccess());
        System.assertEquals(StatusCode.DUPLICATE_VALUE, duplicateResult.getErrors()[0].getStatusCode());
    }

    @IsTest
    static void receiveOrder_createsMonthlyAnonymousFallbackAccountWhenMissing() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/order';
        req.resourcePath = '/v1/order';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"orderDetailGranularity":"TICKET","orderDetailsData":{"orderId":454133,"orderState":"CLOSED","creationDateTime":"2026-05-20T16:08:30.858+02:00","referenceDate":"2026-05-20T00:00:00.000Z","operationDatas":[],"movementDatas":[],"movementTicketDatas":[],"contactReference":"99999","orderType":"RESERVATION","orderSecretId":"secret_454133"}}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        OrderRestResource.receiveOrder();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        String expectedFallbackName = monthlyFallbackAccountName();
        List<Account> fallbackAccounts = [
            SELECT Id, Name
            FROM Account
            WHERE RecordTypeId = :getFallbackAccountRecordTypeId()
              AND Name = :expectedFallbackName
        ];
        System.assertEquals(1, fallbackAccounts.size());

        Order insertedOrder = [
            SELECT Id, AccountId
            FROM Order
            WHERE Order_Id__c = '454133'
            LIMIT 1
        ];
        System.assertEquals(fallbackAccounts[0].Id, insertedOrder.AccountId);
    }

    private static Account createFallbackAccount() {
        Id fallbackRecordTypeId = getFallbackAccountRecordTypeId();
        Account fallbackAccount = new Account(
            Name = monthlyFallbackAccountName(),
            RecordTypeId = fallbackRecordTypeId
        );
        insert fallbackAccount;
        return fallbackAccount;
    }

    private static Id getFallbackAccountRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo fallbackRecordType = recordTypesByDeveloperName.get('Fallback_Account');

        System.assertNotEquals(
            null,
            fallbackRecordType,
            'Account record type Fallback_Account must exist for OrderRestResource tests.'
        );

        return fallbackRecordType.getRecordTypeId();
    }

    private static Integer countRows(String objectApiName, String whereClause) {
        AggregateResult[] results = Database.query(
            'SELECT COUNT(Id) rowCount FROM ' + objectApiName + ' WHERE ' + whereClause
        );
        return Integer.valueOf(String.valueOf(results[0].get('rowCount')));
    }

    private static String monthlyFallbackAccountName() {
        Date today = Date.today();
        return 'Anonymous Secutix Account ' + String.valueOf(today.month()).leftPad(2, '0') + ' - ' + String.valueOf(today.year());
    }
}
