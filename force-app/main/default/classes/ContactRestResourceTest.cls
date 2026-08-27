@IsTest
private class ContactRestResourceTest {
    @IsTest
    static void receiveContact_createsAccountFromStructureAndIndividualData() {
        System.runAs(createAdminUser()) {
            RestRequest req = new RestRequest();
            req.requestUri = '/services/apexrest/v1/contacts';
            req.resourcePath = '/v1/contacts';
            req.httpMethod = 'POST';
            req.requestBody = Blob.valueOf(
                '{"bucket":[{"contactId":1001,"contactNumber":"C-1001","type":"STRUCTURE","state":"ACTIVE","contactOrigin":{"code":"I_BOXOFFICE","translations":{"it":"Biglietteria"}},"individualContact":{"contactNumber":"IC-1001","individualFirstname":"Mario","individualLastname":"Rossi","email":"mario.rossi@example.com","alternativeEmails":["mario.alt@example.com"],"cellPhoneNumber":"+393331234567","individualTitle":"Sig.","individualBirthdate":"1980-02-03","active":true,"login":"mario.rossi@example.com","individualPreferredLanguage":"it","prospect":true,"countryCode":"IT","email1VerificationStatus":"VERIFIED","endValidityDate":"2099-12-31T00:00:00.000+01:00","handicapType":"NONE","addressSalutation":"Gent.le","letterSalutation":"Egr. Sig.","confidentialityLevelEnum":"FREE","cellPhoneNumberVerified":true,"blocked":false,"role":"PUBLIC","verifiedEmail":true,"requiredAccountVerificationEmail":false,"guest":false,"zipCode":"20100"},"structureContact":{"contactNumber":"C-1001","structureOfficialName":"Teatro Demo Official","companyName":"Teatro Demo SRL","name":"Teatro Demo","structureName":"Sala Demo","organizationName":"TFP","legalName":"Teatro Demo SRL","displayName":"Teatro Demo Display","email":"info@demo.it","alternativeEmails":["alt@demo.it"],"cellPhoneNumber":"+3902123456","structureTypeId":21575898,"prospect":true,"community":false,"addressSalutation":"Spett.le","letterSalutation":"Alla cortese attenzione","confidentialityLevelEnum":"FREE","email1VerificationStatus":"UNVERIFIED","role":"PUBLIC","verifiedEmail":false,"requiredAccountVerificationEmail":true},"addresses":[{"contactAddressId":98765,"name":"Sede principale","main":true,"billingAddress":true,"shippingAddress":true,"countryCode":"IT","line1":"Via Roma 1","line2":"Scala A","line3":"Interno 2","street1":"Via Roma 1","street2":"Scala A","street3":"Interno 2","town":"Milano","zipCode":"20100","formattedAddress":"Via Roma 1\\n20100 Milano","documentFormattedAddress":"Gent.le Mario Rossi\\nVia Roma 1\\n20100 Milano","normalizationState":"NORMALIZED","normalizationRating":"HIGH","localityCriteriaElements":["MI"]}]}]}'
            );
            RestContext.request = req;
            RestContext.response = new RestResponse();

            Test.startTest();
            ContactRestResource.receiveContact();
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
            System.assertEquals(1, ((List<Object>) resp.get('accountIds')).size());
            System.assertEquals(1, ((List<Object>) resp.get('externalContactNumbers')).size());

            Account createdAccount = [
                SELECT Name, RecordTypeId, BillingStreet, BillingCity, BillingPostalCode, BillingCountry,
                    Contact_Number__c, Contact_Id__c, State__c, Type, Country_Code__c, AccountSource,
                    End_Validity_Date__c, Role__c, Structure_Type_Id__c,
                    Email__c, Mobile_Phone__c, Individual_Firstname__c, Individual_Lastname__c,
                    Individual_Title__c, Birthdate__c, Active__c, Individual_Contact__c,
                    Structure_Contact__c, Addresses__c, Contact_Origin_Translations__c,
                    Individual_Contact_Number__c, Individual_Login__c, Individual_Preferred_Language__c,
                    Individual_Prospect__c, Individual_Country_Code__c, Individual_Email_Ver_Status__c,
                    Individual_Handicap_Type__c,
                    Individual_Address_Salutation__c, Individual_Letter_Salutation__c,
                    Individual_Confidentiality_Level__c, Individual_Cell_Phone_Verified__c,
                    Individual_Blocked__c, Individual_Verified_Email__c,
                    Individual_Req_Acc_Ver_Email__c, Individual_Guest__c, Individual_Alt_Emails__c
                FROM Account
                WHERE Contact_Number__c = 'C-1001'
                LIMIT 1
            ];
            System.assertEquals('Teatro Demo Official', createdAccount.Name);
            System.assertEquals(getAccountRecordTypeId('StructureAccount'), createdAccount.RecordTypeId);
            System.assertEquals('Milano', createdAccount.BillingCity);
            System.assertEquals('20100', createdAccount.BillingPostalCode);
            System.assertEquals('IT', createdAccount.BillingCountry);
            System.assertEquals('C-1001', createdAccount.Contact_Number__c);
            System.assertEquals('1001', createdAccount.Contact_Id__c);
            System.assertEquals('ACTIVE', createdAccount.State__c);
            System.assertEquals('STRUCTURE', createdAccount.Type);
            System.assertEquals('IT', createdAccount.Country_Code__c);
            System.assertEquals('2099-12-31T00:00:00.000+01:00', createdAccount.End_Validity_Date__c);
            System.assertEquals('PUBLIC', createdAccount.Role__c);
            System.assertEquals(21575898, Integer.valueOf(String.valueOf(createdAccount.Structure_Type_Id__c)));
            System.assertEquals('Secutix', createdAccount.AccountSource);
            System.assertEquals('mario.rossi@example.com', createdAccount.Email__c);
            System.assertEquals('+393331234567', createdAccount.Mobile_Phone__c);
            System.assertEquals('Mario', createdAccount.Individual_Firstname__c);
            System.assertEquals('Rossi', createdAccount.Individual_Lastname__c);
            System.assertEquals('Sig.', createdAccount.Individual_Title__c);
            System.assertEquals(Date.newInstance(1980, 2, 3), createdAccount.Birthdate__c);
            System.assertEquals(true, createdAccount.Active__c);
            System.assert(createdAccount.Individual_Contact__c.contains('"individualFirstname":"Mario"'));
            System.assert(createdAccount.Structure_Contact__c.contains('"companyName":"Teatro Demo SRL"'));
            System.assert(createdAccount.Addresses__c.contains('"town":"Milano"'));
            System.assert(createdAccount.Contact_Origin_Translations__c.contains('"it":"Biglietteria"'));
            System.assertEquals('IC-1001', createdAccount.Individual_Contact_Number__c);
            System.assertEquals('mario.rossi@example.com', createdAccount.Individual_Login__c);
            System.assertEquals('it', createdAccount.Individual_Preferred_Language__c);
            System.assertEquals(true, createdAccount.Individual_Prospect__c);
            System.assertEquals('IT', createdAccount.Individual_Country_Code__c);
            System.assertEquals('VERIFIED', createdAccount.Individual_Email_Ver_Status__c);
            System.assertEquals('NONE', createdAccount.Individual_Handicap_Type__c);
            System.assertEquals('Gent.le', createdAccount.Individual_Address_Salutation__c);
            System.assertEquals('Egr. Sig.', createdAccount.Individual_Letter_Salutation__c);
            System.assertEquals('FREE', createdAccount.Individual_Confidentiality_Level__c);
            System.assertEquals(true, createdAccount.Individual_Cell_Phone_Verified__c);
            System.assertEquals(false, createdAccount.Individual_Blocked__c);
            System.assertEquals(true, createdAccount.Individual_Verified_Email__c);
            System.assertEquals(false, createdAccount.Individual_Req_Acc_Ver_Email__c);
            System.assertEquals(false, createdAccount.Individual_Guest__c);
            System.assert(createdAccount.Individual_Alt_Emails__c.contains('mario.alt@example.com'));

            System.assertEquals(0, [SELECT COUNT() FROM Contact]);
        }
    }

    @IsTest
    static void receiveContact_linksIndividualToStructureByStructureContactNumber() {
        System.runAs(createAdminUser()) {
            RestRequest req = new RestRequest();
            req.requestUri = '/services/apexrest/v1/contacts';
            req.resourcePath = '/v1/contacts';
            req.httpMethod = 'POST';
            req.requestBody = Blob.valueOf(
                '{"bucket":[' +
                    '{"contactId":87792,"contactNumber":"87792","type":"STRUCTURE","state":"VALID","structureContact":{"contactNumber":"87792","structureOfficialName":"LICEO SCIENTIFICO GALILEO GALILEI","community":true,"role":"PUBLIC"}},' +
                    '{"contactId":87793,"contactNumber":"87793","type":"INDIVIDUAL","state":"VALID","individualContact":{"contactNumber":"87793","individualFirstname":"Maria","individualLastname":"ROSSI","role":"RELAY","active":false},"structureContact":{"contactNumber":"87792","structureOfficialName":"LICEO SCIENTIFICO GALILEO GALILEI","role":"PUBLIC"}}' +
                ']}'
            );
            RestContext.request = req;
            RestContext.response = new RestResponse();

            Test.startTest();
            ContactRestResource.receiveContact();
            Test.stopTest();

            System.assertEquals(200, RestContext.response.statusCode);

            Map<String, Account> accountsByContactNumber = new Map<String, Account>();
            for (Account accountRecord : [
                SELECT Id, Name, ParentId, Contact_Number__c, Type, RecordTypeId
                FROM Account
                WHERE Contact_Number__c IN ('87792', '87793')
            ]) {
                accountsByContactNumber.put(accountRecord.Contact_Number__c, accountRecord);
            }

            System.assertEquals(2, accountsByContactNumber.size());
            System.assertEquals('LICEO SCIENTIFICO GALILEO GALILEI', accountsByContactNumber.get('87792').Name);
            System.assertEquals(getAccountRecordTypeId('StructureAccount'), accountsByContactNumber.get('87792').RecordTypeId);
            System.assertEquals('STRUCTURE', accountsByContactNumber.get('87792').Type);
            System.assertEquals('Maria ROSSI', accountsByContactNumber.get('87793').Name);
            System.assertEquals(accountsByContactNumber.get('87792').Id, accountsByContactNumber.get('87793').ParentId);
            System.assertEquals(getAccountRecordTypeId('IndividualAccount'), accountsByContactNumber.get('87793').RecordTypeId);
            System.assertEquals('INDIVIDUAL', accountsByContactNumber.get('87793').Type);
        }
    }

    @IsTest
    static void receiveContact_upsertsExistingAccountByContactNumber() {
        System.runAs(createAdminUser()) {
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

            System.assertEquals(
                200,
                RestContext.response.statusCode,
                RestContext.response.responseBody == null ? null : RestContext.response.responseBody.toString()
            );

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
                SELECT Id, Name, Email__c, Mobile_Phone__c, BillingStreet, BillingCity, BillingPostalCode, Active__c
                FROM Account
                WHERE Contact_Number__c = 'C-2001'
                LIMIT 1
            ];

            System.assertEquals(firstVersion.Id, secondVersion.Id);
            System.assertEquals('Gioia Falzoni Updated', secondVersion.Name);
            System.assertEquals('updated@example.com', secondVersion.Email__c);
            System.assertEquals('+3900000002', secondVersion.Mobile_Phone__c);
            System.assertEquals('Via Due 2', secondVersion.BillingStreet);
            System.assertEquals('Roma', secondVersion.BillingCity);
            System.assertEquals('00100', secondVersion.BillingPostalCode);
            System.assertEquals(false, secondVersion.Active__c);
            System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Contact_Number__c = 'C-2001']);
            System.assertEquals(0, [SELECT COUNT() FROM Contact]);
        }
    }

    @IsTest
    static void receiveContact_fallsBackCountryCodeFromIndividualAndSetsAccountSource() {
        System.runAs(createAdminUser()) {
            RestRequest req = new RestRequest();
            req.requestUri = '/services/apexrest/v1/contacts';
            req.resourcePath = '/v1/contacts';
            req.httpMethod = 'POST';
            req.requestBody = Blob.valueOf(
                '{"contactId":3001,"contactNumber":"C-3001","type":"INDIVIDUAL","state":"VALID","individualContact":{"individualFirstname":"Luca","individualLastname":"Verdi","countryCode":"IT","email":"luca.verdi@example.com","active":true},"addresses":[]}'
            );
            RestContext.request = req;
            RestContext.response = new RestResponse();

            Test.startTest();
            ContactRestResource.receiveContact();
            Test.stopTest();

            Account createdAccount = [
                SELECT RecordTypeId, Type, Country_Code__c, AccountSource
                FROM Account
                WHERE Contact_Number__c = 'C-3001'
                LIMIT 1
            ];

            System.assertEquals(getAccountRecordTypeId('IndividualAccount'), createdAccount.RecordTypeId);
            System.assertEquals('INDIVIDUAL', createdAccount.Type);
            System.assertEquals('IT', createdAccount.Country_Code__c);
            System.assertEquals('Secutix', createdAccount.AccountSource);
        }
    }

    private static User createAdminUser() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(DateTime.now().getTime());
        User userRecord = new User(
            Alias = 'ctrt',
            Email = 'contactresttest+' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ContactRestTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'Europe/Rome',
            Username = 'contactresttest+' + suffix + '@example.com'
        );
        insert userRecord;
        return userRecord;
    }

    private static Id getAccountRecordTypeId(String developerName) {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo recordType = recordTypesByDeveloperName.get(developerName);

        System.assertNotEquals(
            null,
            recordType,
            'Account record type ' + developerName + ' must exist for ContactRestResource tests.'
        );

        return recordType.getRecordTypeId();
    }
}
