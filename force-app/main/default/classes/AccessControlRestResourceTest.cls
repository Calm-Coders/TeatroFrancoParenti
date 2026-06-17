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
            SELECT Id, Name, Order__c
            FROM Access_Control__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(1, insertedRecords.size());
        System.assertEquals('2276812732345698540800199237', insertedRecords[0].Name);
        System.assertEquals(null, insertedRecords[0].Order__c);
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

    @IsTest
    static void receiveAccessControl_linksMatchingOrderByExternalOrderId() {
        Account accountRecord = new Account(Name = 'Access Control Order Account');
        insert accountRecord;

        Order orderRecord = new Order(
            AccountId = accountRecord.Id,
            EffectiveDate = Date.newInstance(2026, 6, 17),
            Status = 'Draft',
            Order_Id__c = '10000404884'
        );
        insert orderRecord;

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

        Access_Control__c insertedRecord = [
            SELECT Order__c, Order_Id__c
            FROM Access_Control__c
            WHERE Barcode__c = '2276812732345698540800199237'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(orderRecord.Id, insertedRecord.Order__c);
        System.assertEquals(10000404884L, Long.valueOf(String.valueOf(insertedRecord.Order_Id__c)));
    }

    @IsTest
    static void receiveAccessControl_updatesExistingRecordWhenBarcodeMatches() {
        Access_Control__c existingRecord = new Access_Control__c(
            Name = '2276812732345698540800199237',
            Barcode__c = '2276812732345698540800199237',
            Ticket_State__c = 'OLD',
            Group_Size__c = 1
        );
        insert existingRecord;

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"barcode":"2276812732345698540800199237","ticketId":10228305597652,"ticketState":"VALID","cancellationCause":"NOT_CANCELLED","tariffCode":"CPGRTKT","productId":101095635789,"productCode":"SCHL","validityStartTime":"2021-10-08T16:00:00.000+02:00","culturalContactNumber":"124","holderInfo":{},"validityEndTime":"2022-10-08T16:00:00.000+02:00","salesChannelCodeMapping":"BO","orderId":10000404884,"creationDate":"2020-09-23T04:38:48.909+02:00","groupSize":10,"price":85000}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AccessControlRestResource.receiveAccessControl();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals(1, [SELECT COUNT() FROM Access_Control__c WHERE Barcode__c = '2276812732345698540800199237']);

        Access_Control__c updatedRecord = [
            SELECT Id, Ticket_Id__c, Ticket_State__c, Group_Size__c, Price__c
            FROM Access_Control__c
            WHERE Id = :existingRecord.Id
        ];
        System.assertEquals(existingRecord.Id, updatedRecord.Id);
        System.assertEquals(10228305597652L, Long.valueOf(String.valueOf(updatedRecord.Ticket_Id__c)));
        System.assertEquals('VALID', updatedRecord.Ticket_State__c);
        System.assertEquals(10, updatedRecord.Group_Size__c);
        System.assertEquals(85000, updatedRecord.Price__c);
    }

    @IsTest
    static void receiveAccessControl_linksMatchingInventoryByProductId() {
        Inventory__c inventoryRecord = new Inventory__c(
            Name = 'Inventory For Access Control',
            Inventory_Id__c = 101095635789L
        );
        insert inventoryRecord;

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"barcode":"INV-LINK-001","ticketId":10228305597652,"ticketState":"VALID","cancellationCause":"NOT_CANCELLED","tariffCode":"CPGRTKT","productId":101095635789,"productCode":"SCHL","validityStartTime":"2021-10-08T16:00:00.000+02:00","culturalContactNumber":"124","holderInfo":{},"validityEndTime":"2022-10-08T16:00:00.000+02:00","salesChannelCodeMapping":"BO","orderId":10000404884,"creationDate":"2020-09-23T04:38:48.909+02:00","groupSize":10,"price":85000}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AccessControlRestResource.receiveAccessControl();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        Access_Control__c insertedRecord = [
            SELECT Inventory__c, Product_Id__c
            FROM Access_Control__c
            WHERE Barcode__c = 'INV-LINK-001'
            LIMIT 1
        ];
        System.assertEquals(inventoryRecord.Id, insertedRecord.Inventory__c);
        System.assertEquals(101095635789L, Long.valueOf(String.valueOf(insertedRecord.Product_Id__c)));
    }

    @IsTest
    static void receiveAccessControl_usesNewestMatchingInventoryWhenDuplicatesExist() {
        Inventory__c olderInventory = new Inventory__c(
            Name = 'Older Access Inventory',
            Inventory_Id__c = 101095635789L
        );
        insert olderInventory;

        Inventory__c newerInventory = new Inventory__c(
            Name = 'Newer Access Inventory',
            Inventory_Id__c = 101095635789L
        );
        insert newerInventory;

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"barcode":"INV-LINK-002","ticketId":10228305597652,"ticketState":"VALID","cancellationCause":"NOT_CANCELLED","tariffCode":"CPGRTKT","productId":101095635789,"productCode":"SCHL","validityStartTime":"2021-10-08T16:00:00.000+02:00","culturalContactNumber":"124","holderInfo":{},"validityEndTime":"2022-10-08T16:00:00.000+02:00","salesChannelCodeMapping":"BO","orderId":10000404884,"creationDate":"2020-09-23T04:38:48.909+02:00","groupSize":10,"price":85000}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AccessControlRestResource.receiveAccessControl();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        Access_Control__c insertedRecord = [
            SELECT Inventory__c
            FROM Access_Control__c
            WHERE Barcode__c = 'INV-LINK-002'
            LIMIT 1
        ];
        System.assertEquals(newerInventory.Id, insertedRecord.Inventory__c);
    }

    @IsTest
    static void receiveAccessControl_usesNewestMatchingOrderWhenDuplicatesExist() {
        Account accountRecord = new Account(Name = 'Duplicate Order Account');
        insert accountRecord;

        Order olderOrder = new Order(
            AccountId = accountRecord.Id,
            EffectiveDate = Date.newInstance(2026, 6, 16),
            Status = 'Draft',
            Order_Id__c = '10000405495'
        );
        insert olderOrder;

        Order newerOrder = new Order(
            AccountId = accountRecord.Id,
            EffectiveDate = Date.newInstance(2026, 6, 17),
            Status = 'Draft',
            Order_Id__c = '10000405495'
        );
        insert newerOrder;

        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '[{"barcode":"2452941492091912458400132443","ticketId":10228404119314,"ticketState":"VALID","cancellationCause":"NOT_CANCELLED","tariffCode":"CPGRTKT","productId":101095635789,"productCode":"SCHL","validityStartTime":"2021-10-27T11:00:00.000+02:00","culturalContactNumber":"106","holderInfo":{},"validityEndTime":"2022-10-27T11:00:00.000+02:00","salesChannelCodeMapping":"B2C","orderId":10000405495,"creationDate":"2021-08-24T05:10:34.597+02:00","groupSize":5,"price":50000}]'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AccessControlRestResource.receiveAccessControl();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        Access_Control__c insertedRecord = [
            SELECT Order__c
            FROM Access_Control__c
            WHERE Barcode__c = '2452941492091912458400132443'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals(newerOrder.Id, insertedRecord.Order__c);
    }

    @IsTest
    static void receiveAccessControl_handlesSinglePayloadWithoutBarcodeUsesTicketName() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"ticketId":10228352025535,"ticketState":"VALID","orderId":10000405208,"groupSize":10,"price":90000}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AccessControlRestResource.receiveAccessControl();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        List<Access_Control__c> ticketNamedRecords = [
            SELECT Name, Ticket_Id__c, Order_Id__c, Barcode__c, Order__c
            FROM Access_Control__c
            ORDER BY CreatedDate DESC
        ];
        Access_Control__c ticketNamedRecord = ticketNamedRecords[0];
        System.assertEquals('Ticket 10228352025535', ticketNamedRecord.Name);
        System.assertEquals(10228352025535L, Long.valueOf(String.valueOf(ticketNamedRecord.Ticket_Id__c)));
        System.assertEquals(null, ticketNamedRecord.Barcode__c);
        System.assertEquals(null, ticketNamedRecord.Order__c);
    }

    @IsTest
    static void receiveAccessControl_handlesSinglePayloadWithoutBarcodeUsesOrderName() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"ticketState":"VALID","orderId":10000405213,"groupSize":5,"price":50000}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AccessControlRestResource.receiveAccessControl();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        List<Access_Control__c> orderNamedRecords = [
            SELECT Name, Ticket_Id__c, Order_Id__c, Barcode__c
            FROM Access_Control__c
            ORDER BY CreatedDate DESC
        ];
        Access_Control__c orderNamedRecord = orderNamedRecords[0];
        System.assertEquals('Order 10000405213', orderNamedRecord.Name);
        System.assertEquals(null, orderNamedRecord.Ticket_Id__c);
        System.assertEquals(10000405213L, Long.valueOf(String.valueOf(orderNamedRecord.Order_Id__c)));
        System.assertEquals(null, orderNamedRecord.Barcode__c);
    }

    @IsTest
    static void receiveAccessControl_rejectsEmptyBody() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('');
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
        System.assertEquals('Request body is required.', resp.get('message'));
    }

    @IsTest
    static void receiveAccessControl_rejectsEmptyPayloadList() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('[]');
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
        System.assertEquals('At least one access payload is required.', resp.get('message'));
    }

    @IsTest
    static void receiveAccessControl_rejectsNonObjectPayloadItem() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('[1]');
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
        System.assertEquals('Each access payload must be a valid JSON object.', resp.get('message'));
    }

    @IsTest
    static void receiveAccessControl_usesDefaultNameWhenNoBarcodeTicketOrOrder() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"ticketState":"VALID","groupSize":1,"price":1000}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AccessControlRestResource.receiveAccessControl();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        Access_Control__c insertedRecord = [
            SELECT Name, Barcode__c, Ticket_Id__c, Order_Id__c
            FROM Access_Control__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assertEquals('Access Control', insertedRecord.Name);
        System.assertEquals(null, insertedRecord.Barcode__c);
        System.assertEquals(null, insertedRecord.Ticket_Id__c);
        System.assertEquals(null, insertedRecord.Order_Id__c);
    }

    @IsTest
    static void receiveAccessControl_logsRequestHeadersWhenPresent() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.addHeader('X-Test-Header', 'abc123');
        req.requestBody = Blob.valueOf(
            '{"ticketState":"VALID","groupSize":1,"price":1000}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AccessControlRestResource.receiveAccessControl();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        Integration_Log__c logRec = [
            SELECT Request_Headers__c
            FROM Integration_Log__c
            WHERE Flow_Name__c = 'AccessControlRestResource.receiveAccessControl'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.assert(logRec.Request_Headers__c.contains('X-Test-Header'));
        System.assert(logRec.Request_Headers__c.contains('abc123'));
    }

    @IsTest
    static void receiveAccessControl_coercesNumericStringValues() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/accesscontrols';
        req.resourcePath = '/v1/accesscontrols';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"barcode":"STRINGS-ONLY","ticketId":"10228305597652","ticketState":"VALID","cancellationCause":"NOT_CANCELLED","tariffCode":"CPGRTKT","productId":"101095635789","productCode":"SCHL","validityStartTime":"2021-10-08T16:00:00.000+02:00","culturalContactNumber":"124","holderInfo":{},"validityEndTime":"2022-10-08T16:00:00.000+02:00","salesChannelCodeMapping":"BO","orderId":"10000404884","creationDate":"2020-09-23T04:38:48.909+02:00","groupSize":"10","price":"85000"}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AccessControlRestResource.receiveAccessControl();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        Access_Control__c insertedRecord = [
            SELECT Ticket_Id__c, Product_Id__c, Order_Id__c, Group_Size__c, Price__c
            FROM Access_Control__c
            WHERE Barcode__c = 'STRINGS-ONLY'
            LIMIT 1
        ];
        System.assertEquals(10228305597652L, Long.valueOf(String.valueOf(insertedRecord.Ticket_Id__c)));
        System.assertEquals(101095635789L, Long.valueOf(String.valueOf(insertedRecord.Product_Id__c)));
        System.assertEquals(10000404884L, Long.valueOf(String.valueOf(insertedRecord.Order_Id__c)));
        System.assertEquals(10, insertedRecord.Group_Size__c);
        System.assertEquals(85000, insertedRecord.Price__c);
    }
}
