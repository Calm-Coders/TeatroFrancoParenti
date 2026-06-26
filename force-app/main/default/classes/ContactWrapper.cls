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
        public Long contactAddressId;
        public Boolean billingAddress;
        public String countryCode;
        public String documentFormattedAddress;
        public String formattedAddress;
        public String line1;
        public String line2;
        public String line3;
        public List<Object> localityCriteriaElements;
        public Boolean main;
        public String name;
        public String normalizationRating;
        public String normalizationState;
        public Boolean shippingAddress;
        public String street1;
        public String street2;
        public String street3;
        public String town;
        public String zipCode;
    }

    global class ContactOriginPayload {
        public String code;
        public Map<String, Object> translations;
    }

    global class IndividualContactPayload {
        public Boolean active;
        public String addressSalutation;
        public List<String> alternativeEmails;
        public Boolean blocked;
        public String cellPhoneNumber;
        public Boolean cellPhoneNumberVerified;
        public String confidentialityLevelEnum;
        public String contactNumber;
        public String countryCode;
        public String email;
        public String email1VerificationStatus;
        public String endValidityDate;
        public Boolean guest;
        public String handicapType;
        public String individualBirthdate;
        public String individualFirstname;
        public String individualLastname;
        public String individualPreferredLanguage;
        public String individualTitle;
        public String letterSalutation;
        public String login;
        public Boolean prospect;
        public Boolean requiredAccountVerificationEmail;
        public String role;
        public Boolean verifiedEmail;
        public String zipCode;
    }

    global class StructureContactPayload {
        public String addressSalutation;
        public List<String> alternativeEmails;
        public String companyName;
        public String cellPhoneNumber;
        public Boolean community;
        public String confidentialityLevelEnum;
        public String contactNumber;
        public String displayName;
        public String email;
        public String email1VerificationStatus;
        public String legalName;
        public String letterSalutation;
        public String name;
        public String organizationName;
        public Boolean prospect;
        public Boolean requiredAccountVerificationEmail;
        public String role;
        public String structureOfficialName;
        public String structureName;
        public Long structureTypeId;
        public Boolean verifiedEmail;
    }
}
