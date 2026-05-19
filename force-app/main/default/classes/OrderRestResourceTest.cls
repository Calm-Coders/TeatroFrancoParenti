@IsTest
private class OrderRestResourceTest {
    @IsTest
    static void receiveOrder_acceptsSinglePayload() {
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
            SELECT Id, AccountId, Status, EffectiveDate, Description
            FROM Order
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertNotEquals(null, insertedOrder.AccountId);
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
}
