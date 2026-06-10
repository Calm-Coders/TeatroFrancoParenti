@IsTest
private class ContactRestResourceTest {
    @IsTest
    static void receiveContact_createsAccountFromStructureAndIndividualData() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/v1/contacts';
        req.resourcePath = '/v1/contacts';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"contactId":1001,"contactNumber":"C-1001","type":"STRUCTURE","state":"ACTIVE","individualContact":{"individualFirstname":"Mario","individualLastname":"Rossi","email":"mario.rossi@example.com","cellPhoneNumber":"+393331234567","individualTitle":"Sig.","individualBirthdate":"1980-02-03","active":true},"structureContact":{"companyName":"Teatro Demo SRL","email":"info@demo.it","cellPhoneNumber":"+3902123456"},"addresses":[{"main":true,"countryCode":"IT","line1":"Via Roma 1","town":"Milano","zipCode":"20100"}]}'
        );
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        ContactRestResource.receiveContact();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);

        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals(true, resp.get('success'));
        System.assertEquals(1, ((List<Object>) resp.get('accountIds')).size());
        System.assertEquals(1, ((List<Object>) resp.get('externalContactNumbers')).size());

        Account createdAccount = [
            SELECT Name, Phone, BillingStreet, BillingCity, BillingPostalCode, BillingCountry,
                Contact_Number__c, Contact_Id__c, State__c, Type__c, Country_Code__c,
                Email__c, Mobile_Phone__c, Individual_Firstname__c, Individual_Lastname__c,
                Individual_Title__c, Birthdate__c, Active__c, Description, Individual_Contact__c,
                Structure_Contact__c, Addresses__c, RecordTypeId
            FROM Account
            WHERE Contact_Number__c = 'C-1001'
            LIMIT 1
        ];
        System.assertEquals('Teatro Demo SRL', createdAccount.Name);
        System.assertEquals('+3902123456', createdAccount.Phone);
        System.assertEquals('Via Roma 1', createdAccount.BillingStreet);
        System.assertEquals('Milano', createdAccount.BillingCity);
        System.assertEquals('20100', createdAccount.BillingPostalCode);
        System.assertEquals('IT', createdAccount.BillingCountry);
        System.assertEquals('C-1001', createdAccount.Contact_Number__c);
        System.assertEquals('1001', createdAccount.Contact_Id__c);
        System.assertEquals('ACTIVE', createdAccount.State__c);
        System.assertEquals('STRUCTURE', createdAccount.Type__c);
        System.assertEquals('IT', createdAccount.Country_Code__c);
        System.assertEquals('mario.rossi@example.com', createdAccount.Email__c);
        System.assertEquals('+393331234567', createdAccount.Mobile_Phone__c);
        System.assertEquals('Mario', createdAccount.Individual_Firstname__c);
        System.assertEquals('Rossi', createdAccount.Individual_Lastname__c);
        System.assertEquals('Sig.', createdAccount.Individual_Title__c);
        System.assertEquals(Date.newInstance(1980, 2, 3), createdAccount.Birthdate__c);
        System.assertEquals(true, createdAccount.Active__c);
        System.assert(createdAccount.Description.contains('Secutix firstName: Mario'));
        System.assert(createdAccount.Individual_Contact__c.contains('"individualFirstname":"Mario"'));
        System.assert(createdAccount.Structure_Contact__c.contains('"companyName":"Teatro Demo SRL"'));
        System.assert(createdAccount.Addresses__c.contains('"town":"Milano"'));
        assertNonFallbackRecordType(createdAccount.RecordTypeId);

        System.assertEquals(0, [SELECT COUNT() FROM Contact]);
    }

    @IsTest
    static void receiveContact_upsertsExistingAccountByContactNumber() {
        RestRequest createReq = new RestRequest();
        createReq.requestUri = '/services/apexrest/v1/contacts';
        createReq.resourcePath = '/v1/contacts';
        createReq.httpMethod = 'POST';
        createReq.requestBody = Blob.valueOf(
            '{"contactId":2001,"contactNumber":"C-2001","type":"INDIVIDUAL","state":"VALID","individualContact":{"individualFirstname":"Gioia","individualLastname":"Falzoni","email":"first@example.com","cellPhoneNumber":"+3900000001","active":true},"addresses":[{"main":true,"countryCode":"IT","line1":"Via Uno 1","town":"Milano","zipCode":"20100"}]}'
        );
        RestContext.request = createReq;
        RestContext.response = new RestResponse();

        ContactRestResource.receiveContact();

        Account firstVersion = [
            SELECT Id, Name, Email__c, Mobile_Phone__c, BillingStreet
            FROM Account
            WHERE Contact_Number__c = 'C-2001'
            LIMIT 1
        ];

        RestRequest updateReq = new RestRequest();
        updateReq.requestUri = '/services/apexrest/v1/contacts';
        updateReq.resourcePath = '/v1/contacts';
        updateReq.httpMethod = 'POST';
        updateReq.requestBody = Blob.valueOf(
            '{"contactId":2001,"contactNumber":"C-2001","type":"INDIVIDUAL","state":"VALID","individualContact":{"individualFirstname":"Gioia","individualLastname":"Falzoni Updated","email":"updated@example.com","cellPhoneNumber":"+3900000002","active":false},"addresses":[{"main":true,"countryCode":"IT","line1":"Via Due 2","town":"Roma","zipCode":"00100"}]}'
        );
        RestContext.request = updateReq;
        RestContext.response = new RestResponse();

        Test.startTest();
        ContactRestResource.receiveContact();
        Test.stopTest();

        Account secondVersion = [
            SELECT Id, Name, Email__c, Mobile_Phone__c, BillingStreet, BillingCity, BillingPostalCode, Active__c, RecordTypeId
            FROM Account
            WHERE Contact_Number__c = 'C-2001'
            LIMIT 1
        ];

        System.assertEquals(firstVersion.Id, secondVersion.Id);
        System.assertEquals('Gioia Falzoni Updated (C-2001)', secondVersion.Name);
        System.assertEquals('updated@example.com', secondVersion.Email__c);
        System.assertEquals('+3900000002', secondVersion.Mobile_Phone__c);
        System.assertEquals('Via Due 2', secondVersion.BillingStreet);
        System.assertEquals('Roma', secondVersion.BillingCity);
        System.assertEquals('00100', secondVersion.BillingPostalCode);
        System.assertEquals(false, secondVersion.Active__c);
        assertNonFallbackRecordType(secondVersion.RecordTypeId);
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Contact_Number__c = 'C-2001']);
        System.assertEquals(0, [SELECT COUNT() FROM Contact]);
    }

    private static void assertNonFallbackRecordType(Id actualRecordTypeId) {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo fallbackRecordType = recordTypesByDeveloperName.get('Fallback_Account');
        if (fallbackRecordType == null) {
            return;
        }

        System.assertNotEquals(
            fallbackRecordType.getRecordTypeId(),
            actualRecordTypeId,
            'Accounts created by ContactRestResource must not use the Fallback_Account record type.'
        );
    }
}
