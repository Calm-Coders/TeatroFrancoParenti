global class OrderWrapper {
    public Payload payload;
    public Map<String, Object> rawPayload;

    global class Payload {
        public OrderDetailsData orderDetailsData;
        public String orderDetailGranularity;
    }

    global class OrderDetailsData {
        public Long orderId;
        public String orderState;
        public String creationDateTime;
        public String referenceDate;
        public String expirationDate;
        public Decimal saleAmount;
        public Decimal preSaleAmount;
        public Decimal reservationAmount;
        public Decimal optionAmount;
        public Decimal waitingAccountBalanceAmount;
        public List<OperationData> operationDatas;
        public List<MovementData> movementDatas;
        public List<MovementTicketData> movementTicketDatas;
        public String contactReference;
        public TranslationContainer salesChannelName;
        public String orderType;
        public List<Object> generatedContiguities;
        public OrderOriginData orderOriginData;
        public String salesChannelType;
        public List<Object> orderInstallmentsToCreate;
        public String orderSecretId;
        public String orderOriginator;
        public String salesChannelCode;
        public CatalogCurrency catalogCurrency;
        public String organizationCode;
        public TranslationContainer organizationName;
        public Boolean multicurrency;
    }

    global class OperationData {
        public Long operationId;
        public Long parentOperationId;
        public String parentOperationLinkType;
        public String kind;
        public String type;
        public Decimal quantity;
        public Decimal basePrice;
        public Decimal unitPrice;
        public Decimal withoutVatTotalAmount;
        public Decimal totalAmount;
        public Long productId;
        public String product;
        public String productCode;
        public Long itemId;
        public Long performanceId;
        public String performance;
        public Long siteId;
        public String site;
        public SiteAddress siteAddress;
        public String space;
        public Long contingentId;
        public String contingent;
        public Boolean numbered;
        public Long seatCategoryId;
        public String seatCategory;
        public Long audienceSubCategoryId;
        public String audienceSubCategory;
        public Integer audienceSubCategoryRank;
        public Boolean audienceSubCategoryRequireAttachment;
        public String audienceSubCategoryExternalDescription;
        public Decimal vatRate;
        public String vatCountryCode;
        public Boolean selfPaidVat;
        public Integer operationNumber;
        public String productFamilyType;
        public String productFamilySubType;
        public String itemDisplayExternalDesignation;
        public List<LocationData> locations;
        public Long fileId;
        public Decimal waitingAccountBalance;
        public String season;
        public String seasonCode;
        public Long seasonId;
        public List<Object> crossSellParentOperationIds;
        public Map<String, Object> comfortVariableValues;
        public Boolean includedInShipmentFee;
        public Long audienceCatId;
        public Boolean exchangeable;
        public CatalogCurrency catalogCurrency;
        public String itemDate;
        public String expirationDate;
        public Long timeslotId;
        public Integer timeslotDuration;
        public Boolean championshipSeasonticket;
        public Boolean fixedSeatSeasonticket;
        public Boolean allSeasonTicketLinesCompetition;
        public VisitGroupData visitGroupData;
        public List<Object> insuredOperationIds;
        public Boolean isNominative;
        public Map<String, Object> priceComponentData;
    }

    global class MovementData {
        public Long movementId;
        public Long operationId;
        public String type;
        public Long seatId;
        public Long saleSeatId;
        public Long seatCategoryId;
        public String seatCategory;
        public Long areaId;
        public String area;
        public Long entranceId;
        public String entrance;
        public String entranceCode;
        public String row;
        public String seatNumber;
        public Long seatQualityId;
        public String seatQuality;
        public String seatQualityCode;
        public Integer yCoordinate;
        public Integer xCoordinate;
        public Long contingentId;
        public String contingent;
        public String contactReference;
        public Integer seatOrientation;
        public Integer instanceNumber;
        public String stageVisibility;
        public String areaKind;
        public Boolean resumed;
        public String attributionMatch;
        public Boolean transferable;
    }

    global class MovementTicketData {
    }

    global class SiteAddress {
        public String firstAddressLine;
        public String zipCode;
        public String locality;
        public String countryCode;
    }

    global class LocationData {
        public String spaceCode;
        public String siteCode;
        public TranslationContainer spaceExternalName;
        public TranslationContainer siteExternalName;
        public SiteAddress siteAddress;
    }

    global class TranslationContainer {
        public List<TranslationValue> translations;
    }

    global class TranslationValue {
        public String locale;
        public String value;
    }

    global class CatalogCurrency {
        public String currencyCode;
        public String symbol;
        public Integer fractionDigit;
        public Decimal minAmount;
    }

    global class VisitGroupData {
        public Long visitGroupId;
        public Integer numberOfAccompaniers;
        public Integer numberOfParticipants;
        public List<Object> fileRemarks;
        public String pricingType;
        public String ticketType;
        public List<Object> groupCriterionElements;
        public Boolean guided;
    }

    global class OrderOriginData {
        public Boolean toCreateToken;
    }
}
