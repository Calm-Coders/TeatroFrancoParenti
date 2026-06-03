@IsTest
private class OrderRestResourceTest {
    @IsTest
    static void receiveOrder_acceptsSinglePayload() {
        Account fallbackAccount = createFallbackAccount();

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

        System.assertEquals(200, RestContext.response.statusCode);

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(true, resp.get('success'));
        System.assertEquals(1, ((List<Object>) resp.get('recordIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('orderIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('orderSecretIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('contactReferences')).size());

        Order insertedOrder = [
            SELECT Id, AccountId, BillToContactId, ShipToContactId, Status, EffectiveDate, Description
            FROM Order
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(fallbackAccount.Id, insertedOrder.AccountId);
        System.assertEquals(null, insertedOrder.BillToContactId);
        System.assertEquals(null, insertedOrder.ShipToContactId);
        System.assertEquals('Draft', insertedOrder.Status);
        System.assert(insertedOrder.Description.contains('Secutix orderId: 10000418846'));
        System.assert(insertedOrder.Description.contains('Secutix orderSecretId: 33e1993b-7e31-4c44-8b8b-2ac646d258a0_10000418846'));
        System.assert(insertedOrder.Description.contains('Secutix contactReference: 5442'));

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

        System.assertEquals(200, RestContext.response.statusCode);

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(true, resp.get('success'));
        System.assertEquals(1, ((List<Object>) resp.get('recordIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('orderIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('orderSecretIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('contactReferences')).size());

        Order insertedOrder = [
            SELECT AccountId, BillToContactId, ShipToContactId, EffectiveDate, Description, Operation_Datas__c, Movement_Datas__c
            FROM Order
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(fallbackAccount.Id, insertedOrder.AccountId);
        System.assertEquals(null, insertedOrder.BillToContactId);
        System.assertEquals(null, insertedOrder.ShipToContactId);
        System.assertEquals(Date.newInstance(2026, 5, 20), insertedOrder.EffectiveDate);
        System.assert(insertedOrder.Description.contains('Secutix orderId: 454129'));
        System.assert(insertedOrder.Description.contains('First operation product: LE VACANZE DEI SIGNORI LAGONIA'));
        System.assert(insertedOrder.Operation_Datas__c.contains('"performanceDate":"2026-05-20T20:15:00.000+02:00"'));
        System.assert(insertedOrder.Movement_Datas__c.contains('"contactReference":"10286"'));
    }

    @IsTest
    static void receiveOrder_linksMatchingContactByShipmentContactNumberAndContactReference() {
        Account accountRecord = new Account(Name = 'Test Contact Account');
        insert accountRecord;

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
        System.assertEquals(accountRecord.Id, ordersByExternalId.get('555001').AccountId);
        System.assertEquals(shipmentContactRecord.Id, ordersByExternalId.get('555001').BillToContactId);
        System.assertEquals(shipmentContactRecord.Id, ordersByExternalId.get('555001').ShipToContactId);
        System.assertEquals(accountRecord.Id, ordersByExternalId.get('555002').AccountId);
        System.assertEquals(referenceContactRecord.Id, ordersByExternalId.get('555002').BillToContactId);
        System.assertEquals(referenceContactRecord.Id, ordersByExternalId.get('555002').ShipToContactId);

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(true, resp.get('success'));
        System.assertEquals(2, ((List<Object>) resp.get('recordIds')).size());
        System.assertEquals(2, ((List<Object>) resp.get('orderIds')).size());
    }

    private static Account createFallbackAccount() {
        Id fallbackRecordTypeId = getFallbackAccountRecordTypeId();
        Account fallbackAccount = new Account(
            Name = 'Test Fallback Account',
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
}
