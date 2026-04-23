@RestResource(urlMapping='/v1/contacts')
global without sharing class ContactRestResource {
    private static final Integer MAX_LOG_LENGTH = 131072;
    private static final Integer MAX_SECUTIX_LONG_TEXT_LENGTH = 32768;

    @HttpPost
    global static void receiveContact() {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }

        Integration_Log__c logRec = new Integration_Log__c();
        initializeLog(logRec, 'ContactRestResource.receiveContact');

        try {
            String rawBody = (RestContext.request == null || RestContext.request.requestBody == null)
                ? null
                : RestContext.request.requestBody.toString();
            logRec.Request_Body__c = abbreviateForLog(rawBody);

            if (String.isBlank(rawBody)) {
                setErrorResponse(400, 'Request body is required.', logRec);
                return;
            }

            List<ContactPayloadEnvelope> payloads;
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
                for (ContactPayloadEnvelope payloadEnvelope : payloads) {
                    validatePayload(payloadEnvelope);
                    Contact newContact = createContact(payloadEnvelope);

                    createdContactIds.add(newContact.Id);
                    if (!String.isBlank(payloadEnvelope.payload.contactNumber)) {
                        externalContactNumbers.add(payloadEnvelope.payload.contactNumber);
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

    private static Contact buildContact(ContactPayloadEnvelope payloadEnvelope) {
        ContactWebhookPayload payload = payloadEnvelope.payload;
        Map<String, Object> rawPayload = payloadEnvelope.rawPayload;
        Contact contactRecord = new Contact();
        IndividualContactPayload individual = payload == null ? null : payload.individualContact;

        contactRecord.FirstName = individual == null ? null : individual.individualFirstname;
        contactRecord.LastName = deriveLastName(payload);
        contactRecord.Email = deriveEmail(payload);
        contactRecord.MobilePhone = deriveMobilePhone(payload);
        contactRecord.Title = individual == null ? null : individual.individualTitle;

        Date birthdate = parseDate(individual == null ? null : individual.individualBirthdate);
        if (birthdate != null) {
            contactRecord.Secutix_Birthdate__c = birthdate;
        }

        AddressPayload primaryAddress = selectPrimaryAddress(payload.addresses);
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
        contactRecord.Secutix_Indicators__c = serializeRawValue(
            rawPayload == null ? null : rawPayload.get('indicators'),
            MAX_SECUTIX_LONG_TEXT_LENGTH
        );

        String description = buildDescription(payload, primaryAddress);
        if (!String.isBlank(description)) {
            contactRecord.Secutix_Description__c = truncateValue(
                description,
                MAX_SECUTIX_LONG_TEXT_LENGTH
            );
        }

        return contactRecord;
    }

    private static List<ContactPayloadEnvelope> deserializePayloads(String rawBody) {
        String trimmedBody = rawBody == null ? null : rawBody.trim();

        if (String.isBlank(trimmedBody)) {
            return new List<ContactPayloadEnvelope>();
        }

        Object rawPayload = JSON.deserializeUntyped(trimmedBody);
        List<ContactPayloadEnvelope> payloads = new List<ContactPayloadEnvelope>();

        if (rawPayload instanceof List<Object>) {
            for (Object item : (List<Object>) rawPayload) {
                payloads.add(buildPayloadEnvelope(item));
            }
            return payloads;
        }

        payloads.add(buildPayloadEnvelope(rawPayload));
        return payloads;
    }

    private static ContactPayloadEnvelope buildPayloadEnvelope(Object rawPayload) {
        if (!(rawPayload instanceof Map<String, Object>)) {
            throw new ContactWebhookException('Each contact payload must be a valid JSON object.');
        }

        Map<String, Object> rawPayloadMap = (Map<String, Object>) rawPayload;
        ContactPayloadEnvelope envelope = new ContactPayloadEnvelope();
        envelope.rawPayload = rawPayloadMap;
        envelope.payload = (ContactWebhookPayload) JSON.deserialize(
            JSON.serialize(rawPayloadMap),
            ContactWebhookPayload.class
        );
        return envelope;
    }

    private static void validatePayload(ContactPayloadEnvelope payloadEnvelope) {
        if (payloadEnvelope == null || payloadEnvelope.payload == null) {
            throw new ContactWebhookException('Each contact payload must be a valid JSON object.');
        }
    }

    private static Contact createContact(ContactPayloadEnvelope payloadEnvelope) {
        ContactWebhookPayload payload = payloadEnvelope.payload;
        Contact contactRecord = buildContact(payloadEnvelope);

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

    private static String deriveLastName(ContactWebhookPayload payload) {
        List<String> candidates = new List<String>();
        IndividualContactPayload individual = payload == null ? null : payload.individualContact;
        StructureContactPayload structure = payload == null ? null : payload.structureContact;

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

    private static String deriveEmail(ContactWebhookPayload payload) {
        List<String> candidates = new List<String>();
        IndividualContactPayload individual = payload == null ? null : payload.individualContact;
        StructureContactPayload structure = payload == null ? null : payload.structureContact;

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

    private static String deriveMobilePhone(ContactWebhookPayload payload) {
        List<String> candidates = new List<String>();
        IndividualContactPayload individual = payload == null ? null : payload.individualContact;
        StructureContactPayload structure = payload == null ? null : payload.structureContact;

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

    private static String buildFallbackAccountName(ContactWebhookPayload payload) {
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

    private static AddressPayload selectPrimaryAddress(List<AddressPayload> addresses) {
        if (addresses == null || addresses.isEmpty()) {
            return null;
        }

        for (AddressPayload candidate : addresses) {
            if (candidate != null && (candidate.main == true || candidate.billingAddress == true || candidate.shippingAddress == true)) {
                return candidate;
            }
        }

        return addresses[0];
    }

    private static String buildStreet(AddressPayload address) {
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

    private static String buildDescription(ContactWebhookPayload payload, AddressPayload address) {
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
        logRec.Response_Body__c = abbreviateForLog(responseJson);
    }

    private static void populateException(Integration_Log__c logRec, Exception e) {
        logRec.Exception_Message__c = abbreviateForLog(e.getMessage());
        logRec.Exception_StackTrace__c = abbreviateForLog(e.getStackTraceString());
    }

    private static String abbreviateForLog(String value) {
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

    global class ContactWebhookPayload {
        public List<AddressPayload> addresses;
        public Long contactId;
        public String contactNumber;
        public ContactOriginPayload contactOrigin;
        public IndividualContactPayload individualContact;
        public StructureContactPayload structureContact;
        public String state;
        public String type;
    }

    global class ContactPayloadEnvelope {
        public ContactWebhookPayload payload;
        public Map<String, Object> rawPayload;
    }

    global class AddressPayload {
        public Boolean billingAddress;
        public String countryCode;
        public String formattedAddress;
        public String line1;
        public String line2;
        public String line3;
        public Boolean main;
        public Boolean shippingAddress;
        public String street1;
        public String street2;
        public String street3;
        public String town;
        public String zipCode;
    }

    global class ContactOriginPayload {
        public String code;
    }

    global class IndividualContactPayload {
        public List<String> alternativeEmails;
        public String cellPhoneNumber;
        public String email;
        public String individualBirthdate;
        public String individualFirstname;
        public String individualLastname;
        public String individualTitle;
    }

    global class StructureContactPayload {
        public List<String> alternativeEmails;
        public String companyName;
        public String cellPhoneNumber;
        public String displayName;
        public String email;
        public String legalName;
        public String name;
        public String organizationName;
        public String structureName;
    }

    global class ContactWebhookException extends Exception {
    }
}
