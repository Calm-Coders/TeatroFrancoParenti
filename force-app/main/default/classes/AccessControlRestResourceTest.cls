@IsTest
private class AccessControlRestResourceTest {
    @IsTest
    static void receiveAccessControl_acceptsPayloadList() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
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
    static void receiveAccessControl_acceptsExtendedPayloadList() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '[{"barcode":"2276812732345698540800199237","ticketId":10228305597652,"ticketState":"VALID","cancellationCause":"NOT_CANCELLED","tariffCode":"CPGRTKT","productId":101095635789,"productCode":"SCHL","validityStartTime":"2021-10-08T16:00:00.000+02:00","culturalContactNumber":"124","holderInfo":{},"validityEndTime":"2022-10-08T16:00:00.000+02:00","salesChannelCodeMapping":"BO","orderId":10000404884,"creationDate":"2020-09-23T04:38:48.909+02:00","groupSize":10,"price":85000},{"barcode":"2452941492091912458400132443","ticketId":10228404119314,"ticketState":"VALID","cancellationCause":"NOT_CANCELLED","tariffCode":"CPGRTKT","productId":101095635789,"productCode":"SCHL","validityStartTime":"2021-10-27T11:00:00.000+02:00","culturalContactNumber":"106","holderInfo":{},"validityEndTime":"2022-10-27T11:00:00.000+02:00","salesChannelCodeMapping":"B2C","orderId":10000405495,"creationDate":"2021-08-24T05:10:34.597+02:00","groupSize":5,"price":50000},{"barcode":"0764921489355619004400132482","ticketId":10228404119315,"ticketState":"VALID","cancellationCause":"NOT_CANCELLED","tariffCode":"CPGRTKT","productId":101095635789,"productCode":"SCHL","validityStartTime":"2021-10-27T11:00:00.000+02:00","culturalContactNumber":"106","holderInfo":{},"validityEndTime":"2022-10-27T11:00:00.000+02:00","salesChannelCodeMapping":"B2C","orderId":10000405495,"creationDate":"2021-08-24T05:10:34.598+02:00","groupSize":5,"price":50000},{"barcode":"0236124824128697718400133805","ticketId":10228352025535,"ticketState":"VALID","cancellationCause":"NOT_CANCELLED","tariffCode":"CPGRTKT","productId":101095635789,"productCode":"SCHL","validityStartTime":"2021-10-06T12:00:00.000+02:00","holderInfo":{},"validityEndTime":"2022-10-06T12:00:00.000+02:00","salesChannelCodeMapping":"BO","orderId":10000405208,"creationDate":"2021-04-23T05:13:10.338+02:00","groupSize":10,"price":90000},{"barcode":"2924224662097669216800132572","ticketId":10228352025537,"ticketState":"VALID","cancellationCause":"NOT_CANCELLED","tariffCode":"CPGRTKT","productId":101095635789,"productCode":"SCHL","validityStartTime":"2021-10-09T15:00:00.000+02:00","culturalContactNumber":"650","holderInfo":{},"validityEndTime":"2022-10-09T15:00:00.000+02:00","salesChannelCodeMapping":"BO","orderId":10000405213,"creationDate":"2021-04-23T05:33:49.953+02:00","groupSize":5,"price":50000}]'
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
        System.assertEquals(5, ((Decimal) resp.get('processedTickets')).intValue());
        System.assertEquals(5, ((List<Object>) resp.get('recordIds')).size());
        System.assertEquals(5, ((List<Object>) resp.get('barcodes')).size());
        System.assertEquals(5, ((List<Object>) resp.get('ticketIds')).size());
        System.assertEquals(5, ((List<Object>) resp.get('orderIds')).size());

        List<Access_Control__c> insertedRecords = [
            SELECT Name, Barcode__c, Cultural_Contact_Number__c, Holder_Info__c, Group_Size__c, Price__c
            FROM Access_Control__c
            WHERE Barcode__c IN (
                '2276812732345698540800199237',
                '2452941492091912458400132443',
                '0764921489355619004400132482',
                '0236124824128697718400133805',
                '2924224662097669216800132572'
            )
        ];
        System.assertEquals(5, insertedRecords.size());

        Map<String, Access_Control__c> byBarcode = new Map<String, Access_Control__c>();
        for (Access_Control__c recordItem : insertedRecords) {
            byBarcode.put(recordItem.Barcode__c, recordItem);
        }

        System.assertEquals('2276812732345698540800199237', byBarcode.get('2276812732345698540800199237').Name);
        System.assertEquals('124', byBarcode.get('2276812732345698540800199237').Cultural_Contact_Number__c);
        System.assertEquals('{}', byBarcode.get('2276812732345698540800199237').Holder_Info__c);
        System.assertEquals(10, byBarcode.get('2276812732345698540800199237').Group_Size__c);
        System.assertEquals(85000, byBarcode.get('2276812732345698540800199237').Price__c);
        System.assertEquals(null, byBarcode.get('0236124824128697718400133805').Cultural_Contact_Number__c);
    }

    @IsTest
    static void receiveAccessControl_rejectsInvalidJson() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
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
