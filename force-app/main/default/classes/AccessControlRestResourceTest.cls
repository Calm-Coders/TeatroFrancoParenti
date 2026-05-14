@IsTest
private class AccessControlRestResourceTest {
    @IsTest
    static void receiveAccessControl_acceptsPayloadList() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/access-control';
        req.resourcePath = '/v1/access-control';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '[{"barcode":"2276812732345698540800199237","ticketId":10228305597652,"ticketState":"VALID","cancellationCause":"NOT_CANCELLED","tariffCode":"CPGRTKT","productId":101095635789,"productCode":"SCHL","validityStartTime":"2021-10-08T16:00:00.000+02:00","culturalContactNumber":"124","holderInfo":{},"validityEndTime":"2022-10-08T16:00:00.000+02:00","salesChannelCodeMapping":"BO","orderId":10000404884,"creationDate":"2020-09-23T04:38:48.909+02:00","groupSize":10,"price":85000}]'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AccessControlRestResource.receiveAccessControl();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(true, resp.get('success'));
        System.assertEquals(1, ((List<Object>) resp.get('recordIds')).size());

        List<Access_Control__c> insertedRecords = [
            SELECT Id, Name
            FROM Access_Control__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(1, insertedRecords.size());
        System.assertEquals('2276812732345698540800199237', insertedRecords[0].Name);
    }

    @IsTest
    static void receiveAccessControl_rejectsInvalidJson() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/access-control';
        req.resourcePath = '/v1/access-control';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('not-json');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AccessControlRestResource.receiveAccessControl();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(false, resp.get('success'));
        System.assertEquals('Invalid JSON payload.', resp.get('message'));
    }
}
