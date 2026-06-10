@RestResource(urlMapping='/v1/contacts')
global without sharing class ContactRestResource {
    private static final Integer MAX_LOG_LENGTH = 131072;
    private static final Integer MAX_SECUTIX_LONG_TEXT_LENGTH = 32768;
    private static final String FLOW_NAME = 'ContactRestResource.receiveContact';
    private static final String FALLBACK_ACCOUNT_RECORD_TYPE = 'Fallback_Account';
    private static final Set<String> REQUIRED_ACCOUNT_FIELDS = new Set<String>{
        'Active__c',
        'Addresses__c',
        'Advantages__c',
        'Authorizations__c',
        'Birthdate__c',
        'Contact_Ballot_Data__c',
        'Contact_Connections__c',
        'Contact_Criteria__c',
        'Contact_Id__c',
        'Contact_Number__c',
        'Contact_Origin__c',
        'Contact_Origin_Detail__c',
        'Contact_Permission__c',
        'Contact_Qualities__c',
        'Country_Code__c',
        'Created_From__c',
        'Creation_Date__c',
        'Date_Last_Modified__c',
        'Email__c',
        'End_Validity_Date__c',
        'Guest__c',
        'Has_Advantages__c',
        'Has_Warning__c',
        'Indicators__c',
        'Individual_Contact__c',
        'Individual_Firstname__c',
        'Individual_Lastname__c',
        'Individual_Title__c',
        'Invalidated_Contact_Qualities__c',
        'Login__c',
        'Login_Last_Update_Time__c',
        'Login_Last_Update_User__c',
        'Mobile_Phone__c',
        'Role__c',
        'Social_Connections__c',
        'State__c',
        'Structure_Contact__c',
        'Type__c'
    };

    @HttpPost
    global static void receiveContact() {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }

        Integration_Log__c logRec = new Integration_Log__c();
        initializeLog(logRec, FLOW_NAME);

        try {
            String rawBody = (RestContext.request == null || RestContext.request.requestBody == null)
                ? null
                : RestContext.request.requestBody.toString();
            logRec.Request_Body__c = trimForLog(rawBody);

            if (String.isBlank(rawBody)) {
                setErrorResponse(400, 'Request body is required.', logRec);
                return;
            }

            List<ContactWrapper> payloads;
            try {
                payloads = deserializePayloads(rawBody);
            } catch (System.JSONException e) {
                populateException(logRec, e);
                setErrorResponse(400, 'Invalid JSON payload.', logRec);
                return;
            }

            if (payloads == null || payloads.isEmpty()) {
                setErrorResponse(400, 'At least one contact payload is required.', logRec);
                return;
            }

            Savepoint sp = Database.setSavepoint();
            List<String> createdAccountIds = new List<String>();
            List<String> externalContactNumbers = new List<String>();

            try {
                for (ContactWrapper contactWrapper : payloads) {
                    validatePayload(contactWrapper);
                    Id accountId = upsertAccount(contactWrapper);

                    createdAccountIds.add(accountId);
                    if (!String.isBlank(contactWrapper.payload.contactNumber)) {
                        externalContactNumbers.add(contactWrapper.payload.contactNumber);
                    }
                }
            } catch (Exception e) {
                Database.rollback(sp);
                throw e;
            }

            Map<String, Object> resp = new Map<String, Object>{
                'success' => true,
                'processedContacts' => payloads.size(),
                'accountIds' => createdAccountIds,
                'externalContactNumbers' => externalContactNumbers,
                'message' => 'Contact payload accepted.'
            };
            setResponse(200, resp, logRec, false);
        } catch (ContactWebhookException e) {
            populateException(logRec, e);
            setErrorResponse(400, e.getMessage(), logRec);
        } catch (DmlException e) {
            populateException(logRec, e);
            setErrorResponse(400, e.getDmlMessage(0), logRec);
        } catch (Exception e) {
            populateException(logRec, e);
            setErrorResponse(500, e.getMessage(), logRec);
        } finally {
            insert logRec;
        }
    }

    private static List<ContactWrapper> deserializePayloads(String rawBody) {
        String trimmedBody = rawBody == null ? null : rawBody.trim();

        if (String.isBlank(trimmedBody)) {
            return new List<ContactWrapper>();
        }

        Object rawPayload = JSON.deserializeUntyped(trimmedBody);
        List<ContactWrapper> payloads = new List<ContactWrapper>();

        if (rawPayload instanceof List<Object>) {
            for (Object item : (List<Object>) rawPayload) {
                payloads.add(buildWrapper(item));
            }
            return payloads;
        }

        if (rawPayload instanceof Map<String, Object>) {
            Map<String, Object> rawPayloadMap = (Map<String, Object>) rawPayload;
            if (rawPayloadMap.containsKey('bucket')) {
                Object bucketPayload = rawPayloadMap.get('bucket');
                if (bucketPayload == null) {
                    return payloads;
                }

                if (!(bucketPayload instanceof List<Object>)) {
                    throw new ContactWebhookException('The bucket node must be a JSON array.');
                }

                for (Object item : (List<Object>) bucketPayload) {
                    payloads.add(buildWrapper(item));
                }
                return payloads;
            }
        }

        payloads.add(buildWrapper(rawPayload));
        return payloads;
    }

    private static ContactWrapper buildWrapper(Object rawPayload) {
        if (!(rawPayload instanceof Map<String, Object>)) {
            throw new ContactWebhookException('Each contact payload must be a valid JSON object.');
        }

        Map<String, Object> rawPayloadMap = (Map<String, Object>) rawPayload;
        ContactWrapper contactWrapper = new ContactWrapper();
        contactWrapper.rawPayload = rawPayloadMap;
        contactWrapper.payload = buildPayload(rawPayloadMap);
        return contactWrapper;
    }

    private static ContactWrapper.Payload buildPayload(Map<String, Object> rawPayloadMap) {
        ContactWrapper.Payload payload = new ContactWrapper.Payload();
        payload.addresses = buildAddresses(rawPayloadMap.get('addresses'));
        payload.contactId = asLong(rawPayloadMap.get('contactId'));
        payload.contactNumber = asString(rawPayloadMap.get('contactNumber'));
        payload.contactOrigin = buildContactOrigin(rawPayloadMap.get('contactOrigin'));
        payload.creationDate = asString(rawPayloadMap.get('creationDate'));
        payload.dateLastModified = asString(rawPayloadMap.get('dateLastModified'));
        payload.endValidityDate = asString(rawPayloadMap.get('endValidityDate'));
        payload.guest = asBoolean(rawPayloadMap.get('guest'));
        payload.hasAdvantages = asBoolean(rawPayloadMap.get('hasAdvantages'));
        payload.hasWarning = asBoolean(rawPayloadMap.get('hasWarning'));
        payload.individualContact = buildIndividualContact(rawPayloadMap.get('individualContact'));
        payload.login = asString(rawPayloadMap.get('login'));
        payload.loginLastUpdateTime = asString(rawPayloadMap.get('loginLastUpdateTime'));
        payload.loginLastUpdateUser = asString(rawPayloadMap.get('loginLastUpdateUser'));
        payload.role = asString(rawPayloadMap.get('role'));
        payload.state = asString(rawPayloadMap.get('state'));
        payload.structureContact = buildStructureContact(rawPayloadMap.get('structureContact'));
        payload.type = asString(rawPayloadMap.get('type'));
        return payload;
    }

    private static List<ContactWrapper.AddressPayload> buildAddresses(Object rawAddresses) {
        List<ContactWrapper.AddressPayload> addresses = new List<ContactWrapper.AddressPayload>();
        if (!(rawAddresses instanceof List<Object>)) {
            return addresses;
        }

        for (Object rawAddress : (List<Object>) rawAddresses) {
            if (!(rawAddress instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> rawAddressMap = (Map<String, Object>) rawAddress;
            ContactWrapper.AddressPayload address = new ContactWrapper.AddressPayload();
            address.billingAddress = asBoolean(rawAddressMap.get('billingAddress'));
            address.countryCode = asString(rawAddressMap.get('countryCode'));
            address.formattedAddress = asString(rawAddressMap.get('formattedAddress'));
            address.line1 = asString(rawAddressMap.get('line1'));
            address.line2 = asString(rawAddressMap.get('line2'));
            address.line3 = asString(rawAddressMap.get('line3'));
            address.main = asBoolean(rawAddressMap.get('main'));
            address.shippingAddress = asBoolean(rawAddressMap.get('shippingAddress'));
            address.street1 = asString(rawAddressMap.get('street1'));
            address.street2 = asString(rawAddressMap.get('street2'));
            address.street3 = asString(rawAddressMap.get('street3'));
            address.town = asString(rawAddressMap.get('town'));
            address.zipCode = asString(rawAddressMap.get('zipCode'));
            addresses.add(address);
        }

        return addresses;
    }

    private static ContactWrapper.ContactOriginPayload buildContactOrigin(Object rawContactOrigin) {
        if (!(rawContactOrigin instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> rawContactOriginMap = (Map<String, Object>) rawContactOrigin;
        ContactWrapper.ContactOriginPayload contactOrigin = new ContactWrapper.ContactOriginPayload();
        contactOrigin.code = asString(rawContactOriginMap.get('code'));
        return contactOrigin;
    }

    private static ContactWrapper.IndividualContactPayload buildIndividualContact(Object rawIndividualContact) {
        if (!(rawIndividualContact instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> rawIndividualMap = (Map<String, Object>) rawIndividualContact;
        ContactWrapper.IndividualContactPayload individual = new ContactWrapper.IndividualContactPayload();
        individual.active = asBoolean(rawIndividualMap.get('active'));
        individual.alternativeEmails = asStringList(rawIndividualMap.get('alternativeEmails'));
        individual.cellPhoneNumber = asString(rawIndividualMap.get('cellPhoneNumber'));
        individual.email = asString(rawIndividualMap.get('email'));
        individual.individualBirthdate = asString(rawIndividualMap.get('individualBirthdate'));
        individual.individualFirstname = asString(rawIndividualMap.get('individualFirstname'));
        individual.individualLastname = asString(rawIndividualMap.get('individualLastname'));
        individual.individualTitle = asString(rawIndividualMap.get('individualTitle'));
        return individual;
    }

    private static ContactWrapper.StructureContactPayload buildStructureContact(Object rawStructureContact) {
        if (!(rawStructureContact instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> rawStructureMap = (Map<String, Object>) rawStructureContact;
        ContactWrapper.StructureContactPayload structure = new ContactWrapper.StructureContactPayload();
        structure.alternativeEmails = asStringList(rawStructureMap.get('alternativeEmails'));
        structure.companyName = asString(rawStructureMap.get('companyName'));
        structure.cellPhoneNumber = asString(rawStructureMap.get('cellPhoneNumber'));
        structure.displayName = asString(rawStructureMap.get('displayName'));
        structure.email = asString(rawStructureMap.get('email'));
        structure.legalName = asString(rawStructureMap.get('legalName'));
        structure.name = asString(rawStructureMap.get('name'));
        structure.organizationName = asString(rawStructureMap.get('organizationName'));
        structure.structureName = asString(rawStructureMap.get('structureName'));
        return structure;
    }

    private static void validatePayload(ContactWrapper contactWrapper) {
        if (contactWrapper == null || contactWrapper.payload == null) {
            throw new ContactWebhookException('Each contact payload must be a valid JSON object.');
        }
    }

    private static Id upsertAccount(ContactWrapper contactWrapper) {
        ContactWrapper.Payload payload = contactWrapper.payload;
        validateRequiredAccountFields();
        Account accountRecord = buildAccount(contactWrapper);
        if (String.isBlank(payload == null ? null : payload.contactNumber)) {
            throw new ContactWebhookException('contactNumber is required for account upsert.');
        }

        upsert accountRecord Contact_Number__c;
        return accountRecord.Id;
    }

    private static Account buildAccount(ContactWrapper contactWrapper) {
        ContactWrapper.Payload payload = contactWrapper == null ? null : contactWrapper.payload;
        Map<String, Object> rawPayload = contactWrapper == null ? null : contactWrapper.rawPayload;
        Account accountRecord = new Account();
        Id accountRecordTypeId = getInboundAccountRecordTypeId();
        if (accountRecordTypeId != null) {
            accountRecord.RecordTypeId = accountRecordTypeId;
        }
        accountRecord.Name = deriveAccountName(payload);

        ContactWrapper.AddressPayload primaryAddress = selectPrimaryAddress(payload == null ? null : payload.addresses);
        if (primaryAddress != null) {
            accountRecord.BillingStreet = buildStreet(primaryAddress);
            accountRecord.BillingCity = primaryAddress.town;
            accountRecord.BillingPostalCode = primaryAddress.zipCode;
            accountRecord.BillingCountry = primaryAddress.countryCode;
        }

        accountRecord.Phone = deriveAccountPhone(payload);
        accountRecord.Description = buildAccountDescription(payload, primaryAddress);

        ContactWrapper.IndividualContactPayload individual = payload == null ? null : payload.individualContact;
        setSObjectField(accountRecord, 'Individual_Firstname__c', truncateValue(individual == null ? null : individual.individualFirstname, 80));
        setSObjectField(accountRecord, 'Individual_Lastname__c', truncateValue(deriveLastName(payload), 80));
        setSObjectField(accountRecord, 'Individual_Title__c', truncateValue(individual == null ? null : individual.individualTitle, 80));
        setSObjectField(accountRecord, 'Email__c', deriveEmail(payload));
        setSObjectField(accountRecord, 'Mobile_Phone__c', deriveMobilePhone(payload));
        setSObjectField(accountRecord, 'Active__c', individual == null ? null : individual.active);

        Date birthdate = parseDate(individual == null ? null : individual.individualBirthdate);
        if (birthdate != null) {
            setSObjectField(accountRecord, 'Birthdate__c', birthdate);
        }

        setSObjectField(
            accountRecord,
            'Contact_Id__c',
            truncateValue(payload == null || payload.contactId == null ? null : String.valueOf(payload.contactId), 30)
        );
        setSObjectField(accountRecord, 'Contact_Number__c', truncateValue(payload == null ? null : payload.contactNumber, 80));
        setSObjectField(
            accountRecord,
            'Contact_Origin__c',
            truncateValue(payload == null || payload.contactOrigin == null ? null : payload.contactOrigin.code, 80)
        );
        setSObjectField(accountRecord, 'State__c', truncateValue(payload == null ? null : payload.state, 40));
        setSObjectField(accountRecord, 'Type__c', truncateValue(payload == null ? null : payload.type, 40));
        setSObjectField(
            accountRecord,
            'Country_Code__c',
            truncateValue(primaryAddress == null ? null : primaryAddress.countryCode, 10)
        );
        setSObjectField(
            accountRecord,
            'Authorizations__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('authorizations'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Contact_Ballot_Data__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('contactBallotData'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Contact_Connections__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('contactConnections'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Contact_Criteria__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('contactCriteria'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Contact_Origin_Detail__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('contactOrigin'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Contact_Permission__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('contactPermission'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Contact_Qualities__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('contactQualities'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Created_From__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('createdFrom'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Addresses__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('addresses'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Advantages__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('advantages'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Individual_Contact__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('individualContact'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Indicators__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('indicators'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Invalidated_Contact_Qualities__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('invalidatedContactQualities'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Social_Connections__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('socialConnections'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(
            accountRecord,
            'Structure_Contact__c',
            serializeRawValue(rawPayload == null ? null : rawPayload.get('structureContact'), MAX_SECUTIX_LONG_TEXT_LENGTH)
        );
        setSObjectField(accountRecord, 'Creation_Date__c', truncateValue(payload == null ? null : payload.creationDate, 40));
        setSObjectField(accountRecord, 'Date_Last_Modified__c', truncateValue(payload == null ? null : payload.dateLastModified, 40));
        setSObjectField(accountRecord, 'End_Validity_Date__c', truncateValue(payload == null ? null : payload.endValidityDate, 40));
        setSObjectField(accountRecord, 'Has_Advantages__c', payload == null ? null : payload.hasAdvantages);
        setSObjectField(accountRecord, 'Has_Warning__c', payload == null ? null : payload.hasWarning);
        setSObjectField(accountRecord, 'Guest__c', payload == null ? null : payload.guest);
        setSObjectField(accountRecord, 'Login__c', truncateValue(payload == null ? null : payload.login, 255));
        setSObjectField(accountRecord, 'Login_Last_Update_Time__c', truncateValue(payload == null ? null : payload.loginLastUpdateTime, 40));
        setSObjectField(accountRecord, 'Login_Last_Update_User__c', truncateValue(payload == null ? null : payload.loginLastUpdateUser, 80));
        setSObjectField(accountRecord, 'Role__c', truncateValue(payload == null ? null : payload.role, 40));
        return accountRecord;
    }

    private static void validateRequiredAccountFields() {
        Map<String, SObjectField> fieldMap = Account.SObjectType.getDescribe().fields.getMap();
        List<String> missingFields = new List<String>();

        for (String fieldApiName : REQUIRED_ACCOUNT_FIELDS) {
            if (!fieldMap.containsKey(fieldApiName)) {
                missingFields.add(fieldApiName);
            }
        }

        if (!missingFields.isEmpty()) {
            missingFields.sort();
            throw new ContactWebhookException(
                'Missing required Account fields for ContactRestResource: ' + String.join(missingFields, ', ')
            );
        }
    }

    private static Id getInboundAccountRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
        if (recordTypesByDeveloperName == null || recordTypesByDeveloperName.isEmpty()) {
            return null;
        }

        for (String developerName : recordTypesByDeveloperName.keySet()) {
            Schema.RecordTypeInfo recordTypeInfo = recordTypesByDeveloperName.get(developerName);
            if (
                recordTypeInfo != null &&
                recordTypeInfo.isAvailable() &&
                developerName != FALLBACK_ACCOUNT_RECORD_TYPE
            ) {
                return recordTypeInfo.getRecordTypeId();
            }
        }

        return null;
    }

    private static String deriveLastName(ContactWrapper.Payload payload) {
        List<String> candidates = new List<String>();
        ContactWrapper.IndividualContactPayload individual = payload == null ? null : payload.individualContact;
        ContactWrapper.StructureContactPayload structure = payload == null ? null : payload.structureContact;

        if (individual != null) {
            addDistinctValue(candidates, individual.individualLastname);
        }

        if (structure != null) {
            addDistinctValue(candidates, structure.name);
            addDistinctValue(candidates, structure.structureName);
            addDistinctValue(candidates, structure.companyName);
            addDistinctValue(candidates, structure.organizationName);
            addDistinctValue(candidates, structure.legalName);
            addDistinctValue(candidates, structure.displayName);
        }

        if (payload != null) {
            if (!String.isBlank(payload.contactNumber)) {
                candidates.add('Secutix ' + payload.contactNumber);
            }

            if (payload.contactId != null) {
                candidates.add('Secutix ' + String.valueOf(payload.contactId));
            }
        }

        return truncateValue(firstNonBlankValue(candidates) == null ? 'Secutix Account' : firstNonBlankValue(candidates), 80);
    }

    private static String deriveEmail(ContactWrapper.Payload payload) {
        List<String> candidates = new List<String>();
        ContactWrapper.IndividualContactPayload individual = payload == null ? null : payload.individualContact;
        ContactWrapper.StructureContactPayload structure = payload == null ? null : payload.structureContact;

        if (individual != null) {
            addDistinctValue(candidates, individual.email);
            addValues(candidates, individual.alternativeEmails);
        }

        if (structure != null) {
            addDistinctValue(candidates, structure.email);
            addValues(candidates, structure.alternativeEmails);
        }

        return firstNonBlankValue(candidates);
    }

    private static String deriveMobilePhone(ContactWrapper.Payload payload) {
        List<String> candidates = new List<String>();
        ContactWrapper.IndividualContactPayload individual = payload == null ? null : payload.individualContact;
        ContactWrapper.StructureContactPayload structure = payload == null ? null : payload.structureContact;

        if (individual != null) {
            addDistinctValue(candidates, individual.cellPhoneNumber);
        }

        if (structure != null) {
            addDistinctValue(candidates, structure.cellPhoneNumber);
        }

        return firstNonBlankValue(candidates);
    }

    private static String deriveAccountName(ContactWrapper.Payload payload) {
        String structureAccountName = deriveStructureAccountName(payload);
        if (!String.isBlank(structureAccountName)) {
            return structureAccountName;
        }

        List<String> nameParts = new List<String>();
        if (payload != null && payload.individualContact != null) {
            addDistinctValue(nameParts, payload.individualContact.individualFirstname);
            addDistinctValue(nameParts, payload.individualContact.individualLastname);
        }

        String baseName = nameParts.isEmpty() ? 'Secutix Account' : String.join(nameParts, ' ');
        if (payload != null && !String.isBlank(payload.contactNumber)) {
            baseName += ' (' + payload.contactNumber + ')';
        }

        return truncateValue(baseName, 255);
    }

    private static String deriveStructureAccountName(ContactWrapper.Payload payload) {
        List<String> nameParts = new List<String>();
        ContactWrapper.StructureContactPayload structure = payload == null ? null : payload.structureContact;

        if (structure != null) {
            addDistinctValue(nameParts, structure.name);
            addDistinctValue(nameParts, structure.structureName);
            addDistinctValue(nameParts, structure.companyName);
            addDistinctValue(nameParts, structure.organizationName);
            addDistinctValue(nameParts, structure.legalName);
            addDistinctValue(nameParts, structure.displayName);
        }

        return nameParts.isEmpty() ? null : truncateValue(String.join(nameParts, ' '), 255);
    }

    private static String deriveAccountPhone(ContactWrapper.Payload payload) {
        List<String> candidates = new List<String>();
        ContactWrapper.StructureContactPayload structure = payload == null ? null : payload.structureContact;
        ContactWrapper.IndividualContactPayload individual = payload == null ? null : payload.individualContact;

        if (structure != null) {
            addDistinctValue(candidates, structure.cellPhoneNumber);
        }

        if (individual != null) {
            addDistinctValue(candidates, individual.cellPhoneNumber);
        }

        return firstNonBlankValue(candidates);
    }

    private static ContactWrapper.AddressPayload selectPrimaryAddress(List<ContactWrapper.AddressPayload> addresses) {
        if (addresses == null || addresses.isEmpty()) {
            return null;
        }

        for (ContactWrapper.AddressPayload candidate : addresses) {
            if (candidate != null && (candidate.main == true || candidate.billingAddress == true || candidate.shippingAddress == true)) {
                return candidate;
            }
        }

        return addresses[0];
    }

    private static String buildStreet(ContactWrapper.AddressPayload address) {
        if (address == null) {
            return null;
        }

        List<String> streetLines = new List<String>();
        addDistinctValue(streetLines, address.line1);
        addDistinctValue(streetLines, address.line2);
        addDistinctValue(streetLines, address.line3);
        addDistinctValue(streetLines, address.street1);
        addDistinctValue(streetLines, address.street2);
        addDistinctValue(streetLines, address.street3);

        if (streetLines.isEmpty()) {
            addDistinctValue(streetLines, address.formattedAddress);
        }

        return streetLines.isEmpty() ? null : String.join(streetLines, '\n');
    }

    private static String buildDescription(ContactWrapper.Payload payload, ContactWrapper.AddressPayload address) {
        List<String> lines = new List<String>();

        addLabelValue(lines, 'Secutix contactId', payload.contactId == null ? null : String.valueOf(payload.contactId));
        addLabelValue(lines, 'Secutix contactNumber', payload.contactNumber);
        addLabelValue(lines, 'Secutix type', payload.type);
        addLabelValue(lines, 'Secutix state', payload.state);
        addLabelValue(lines, 'Secutix origin', payload.contactOrigin == null ? null : payload.contactOrigin.code);
        addLabelValue(lines, 'Secutix countryCode', address == null ? null : address.countryCode);

        return lines.isEmpty() ? null : String.join(lines, '\n');
    }

    private static String buildAccountDescription(ContactWrapper.Payload payload, ContactWrapper.AddressPayload address) {
        List<String> lines = new List<String>();
        ContactWrapper.IndividualContactPayload individual = payload == null ? null : payload.individualContact;

        addLabelValue(lines, 'Secutix firstName', individual == null ? null : individual.individualFirstname);
        addLabelValue(lines, 'Secutix lastName', individual == null ? null : individual.individualLastname);
        addLabelValue(lines, 'Secutix title', individual == null ? null : individual.individualTitle);
        addLabelValue(lines, 'Secutix email', deriveEmail(payload));
        addLabelValue(lines, 'Secutix mobilePhone', deriveMobilePhone(payload));
        addLabelValue(lines, 'Secutix birthdate', individual == null ? null : individual.individualBirthdate);

        String baseDescription = buildDescription(payload, address);
        if (!String.isBlank(baseDescription)) {
            lines.add(baseDescription);
        }

        return lines.isEmpty() ? null : truncateValue(String.join(lines, '\n'), MAX_SECUTIX_LONG_TEXT_LENGTH);
    }

    private static void setSObjectField(SObject recordItem, String fieldApiName, Object value) {
        if (recordItem == null || String.isBlank(fieldApiName) || value == null) {
            return;
        }

        Map<String, SObjectField> fieldMap = recordItem.getSObjectType().getDescribe().fields.getMap();
        if (!fieldMap.containsKey(fieldApiName)) {
            return;
        }

        DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();
        Object coercedValue = coerceFieldValue(fieldDescribe, value);
        if (coercedValue != null) {
            recordItem.put(fieldApiName, coercedValue);
        }
    }

    private static Object coerceFieldValue(DescribeFieldResult fieldDescribe, Object value) {
        if (fieldDescribe == null || value == null) {
            return null;
        }

        if (value instanceof Date && fieldDescribe.getType() == DisplayType.Date) {
            return value;
        }

        if (value instanceof Boolean && fieldDescribe.getType() == DisplayType.Boolean) {
            return value;
        }

        String stringValue = String.valueOf(value);
        DisplayType fieldType = fieldDescribe.getType();

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
            if (stringValue == 'true') {
                return true;
            }

            if (stringValue == 'false') {
                return false;
            }

            return null;
        }

        if (fieldType == DisplayType.Date) {
            return parseDate(stringValue);
        }

        return null;
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

    private static void addDistinctValue(List<String> values, String value) {
        if (!String.isBlank(value) && !values.contains(value)) {
            values.add(value);
        }
    }

    private static void addValues(List<String> target, List<String> source) {
        if (source == null) {
            return;
        }

        for (String value : source) {
            addDistinctValue(target, value);
        }
    }

    private static void addLabelValue(List<String> values, String label, String value) {
        if (!String.isBlank(value)) {
            values.add(label + ': ' + value);
        }
    }

    private static String firstNonBlankValue(List<String> values) {
        if (values == null) {
            return null;
        }

        for (String value : values) {
            if (!String.isBlank(value)) {
                return value;
            }
        }

        return null;
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
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

    private static List<String> asStringList(Object value) {
        List<String> values = new List<String>();
        if (!(value instanceof List<Object>)) {
            return values;
        }

        for (Object item : (List<Object>) value) {
            if (item != null) {
                values.add(String.valueOf(item));
            }
        }

        return values;
    }

    private static String truncateValue(String value, Integer maxLength) {
        if (value == null || maxLength == null || value.length() <= maxLength) {
            return value;
        }

        return value.substring(0, maxLength);
    }

    private static String serializeRawValue(Object value, Integer maxLength) {
        if (value == null) {
            return null;
        }

        return truncateValue(JSON.serialize(value), maxLength);
    }

    private static void setErrorResponse(Integer statusCode, String message, Integration_Log__c logRec) {
        setResponse(
            statusCode,
            new Map<String, Object>{
                'success' => false,
                'message' => message
            },
            logRec,
            true
        );
    }

    private static void setResponse(
        Integer statusCode,
        Map<String, Object> payload,
        Integration_Log__c logRec,
        Boolean isError
    ) {
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

    global class ContactWebhookException extends Exception {
    }
}
