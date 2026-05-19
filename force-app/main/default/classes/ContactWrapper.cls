global class ContactWrapper {
    public Payload payload;
    public Map<String, Object> rawPayload;

    global class RequestWrapper {
        public List<Payload> bucket;
        public Map<String, Object> destination;
    }

    global class Payload {
        public List<AddressPayload> addresses;
        public List<Object> advantages;
        public List<Object> authorizations;
        public String creationDate;
        public List<Object> contactBallotData;
        public List<Object> contactConnections;
        public List<Object> contactCriteria;
        public Long contactId;
        public List<Object> contactQualities;
        public String contactNumber;
        public Object contactPermission;
        public ContactOriginPayload contactOrigin;
        public Object createdFrom;
        public String dateLastModified;
        public String endValidityDate;
        public Boolean guest;
        public Boolean hasAdvantages;
        public Boolean hasWarning;
        public List<Object> indicators;
        public List<Object> invalidatedContactQualities;
        public IndividualContactPayload individualContact;
        public String login;
        public String loginLastUpdateTime;
        public String loginLastUpdateUser;
        public String role;
        public List<Object> socialConnections;
        public String state;
        public StructureContactPayload structureContact;
        public String type;
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
}
