@RestResource(urlMapping='/v1/contacts')
global without sharing class ContactRestResource {
    private static final Integer MAX_LOG_LENGTH = 131072;
    private static final Integer MAX_SECUTIX_LONG_TEXT_LENGTH = 32768;
    private static final String FLOW_NAME = 'ContactRestResource.receiveContact';

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
            List<String> createdContactIds = new List<String>();
            List<String> externalContactNumbers = new List<String>();

            try {
                for (ContactWrapper contactWrapper : payloads) {
                    validatePayload(contactWrapper);
                    Contact newContact = createContact(contactWrapper);

                    createdContactIds.add(newContact.Id);
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
                'contactIds' => createdContactIds,
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

    private static Contact buildContact(ContactWrapper contactWrapper) {
        ContactWrapper.Payload payload = contactWrapper.payload;
        Map<String, Object> rawPayload = contactWrapper.rawPayload;
        Contact contactRecord = new Contact();
        ContactWrapper.IndividualContactPayload individual = payload == null ? null : payload.individualContact;

        contactRecord.FirstName = individual == null ? null : individual.individualFirstname;
        contactRecord.LastName = deriveLastName(payload);
        contactRecord.Email = deriveEmail(payload);
        contactRecord.MobilePhone = deriveMobilePhone(payload);
        contactRecord.Title = individual == null ? null : individual.individualTitle;

        Date birthdate = parseDate(individual == null ? null : individual.individualBirthdate);
        if (birthdate != null) {
            contactRecord.Secutix_Birthdate__c = birthdate;
        }

        ContactWrapper.AddressPayload primaryAddress = selectPrimaryAddress(payload.addresses);
        if (primaryAddress != null) {
            contactRecord.MailingStreet = buildStreet(primaryAddress);
            contactRecord.MailingCity = primaryAddress.town;
            contactRecord.MailingPostalCode = primaryAddress.zipCode;
        }

        contactRecord.Secutix_Contact_Id__c = truncateValue(
            payload.contactId == null ? null : String.valueOf(payload.contactId),
            30
        );
        contactRecord.Secutix_Contact_Number__c = truncateValue(payload.contactNumber, 80);
        contactRecord.Secutix_Contact_Origin__c = truncateValue(
            payload.contactOrigin == null ? null : payload.contactOrigin.code,
            80
        );
        contactRecord.Secutix_State__c = truncateValue(payload.state, 40);
        contactRecord.Secutix_Type__c = truncateValue(payload.type, 40);
        contactRecord.Secutix_Country_Code__c = truncateValue(
            primaryAddress == null ? null : primaryAddress.countryCode,
            10
        );
        contactRecord.Secutix_Authorizations__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('authorizations'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Contact_Ballot_Data__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('contactBallotData'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Contact_Connections__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('contactConnections'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Contact_Criteria__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('contactCriteria'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Contact_Origin_Detail__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('contactOrigin'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Contact_Permission__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('contactPermission'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Contact_Qualities__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('contactQualities'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Created_From__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('createdFrom'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Addresses__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('addresses'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Advantages__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('advantages'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Individual_Contact__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('individualContact'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Secutix_Indicators__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('indicators'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Invalidated_Contact_Qualities__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('invalidatedContactQualities'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Social_Connections__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('socialConnections'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );
        contactRecord.Structure_Contact__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('structureContact'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );

        contactRecord.Creation_Date__c = truncateValue(payload.creationDate, 40);
        contactRecord.Date_Last_Modified__c = truncateValue(payload.dateLastModified, 40);
        contactRecord.End_Validity_Date__c = truncateValue(payload.endValidityDate, 40);
        contactRecord.Has_Advantages__c = payload.hasAdvantages;
        contactRecord.Has_Warning__c = payload.hasWarning;
        contactRecord.Guest__c = payload.guest;
        contactRecord.Login__c = truncateValue(payload.login, 255);
        contactRecord.Login_Last_Update_Time__c = truncateValue(payload.loginLastUpdateTime, 40);
        contactRecord.Login_Last_Update_User__c = truncateValue(payload.loginLastUpdateUser, 80);
        contactRecord.Role__c = truncateValue(payload.role, 40);

        String description = buildDescription(payload, primaryAddress);
        if (!String.isBlank(description)) {
            contactRecord.Secutix_Description__c = truncateValue(
                description,
                MAX_SECUTIX_LONG_TEXT_LENGTH
            );
        }

        return contactRecord;
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

    private static Contact createContact(ContactWrapper contactWrapper) {
        ContactWrapper.Payload payload = contactWrapper.payload;
        Contact contactRecord = buildContact(contactWrapper);

        try {
            insert contactRecord;
            return contactRecord;
        } catch (DmlException e) {
            if (!shouldRetryWithFallbackAccount(e)) {
                throw e;
            }

            Savepoint sp = Database.setSavepoint();
            try {
                Account fallbackAccount = new Account(
                    Name = buildFallbackAccountName(payload)
                );
                insert fallbackAccount;

                contactRecord.AccountId = fallbackAccount.Id;
                insert contactRecord;
                return contactRecord;
            } catch (DmlException retryException) {
                Database.rollback(sp);
                throw retryException;
            }
        }
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

        return truncateValue(
            firstNonBlankValue(candidates) == null ? 'Secutix Contact' : firstNonBlankValue(candidates),
            80
        );
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

    private static Boolean shouldRetryWithFallbackAccount(DmlException e) {
        String message = e == null ? null : e.getMessage();
        if (String.isBlank(message)) {
            return false;
        }

        String normalizedMessage = message.toLowerCase();
        return (normalizedMessage.contains('accountid') || normalizedMessage.contains('account')) &&
            (normalizedMessage.contains('required') || normalizedMessage.contains('missing'));
    }

    private static String buildFallbackAccountName(ContactWrapper.Payload payload) {
        List<String> nameParts = new List<String>();

        if (payload != null && payload.individualContact != null) {
            addDistinctValue(nameParts, payload.individualContact.individualFirstname);
            addDistinctValue(nameParts, payload.individualContact.individualLastname);
        }

        String baseName = nameParts.isEmpty() ? 'Secutix Contact' : String.join(nameParts, ' ');
        if (payload != null && !String.isBlank(payload.contactNumber)) {
            baseName += ' (' + payload.contactNumber + ')';
        }

        return ('Secutix - ' + baseName).left(255);
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
