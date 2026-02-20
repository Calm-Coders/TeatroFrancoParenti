@RestResource(urlMapping='/v1/accounts')
global without sharing class AccountRestResource {
    @HttpPost
    global static void createAccount() {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }

        Integration_Log__c logRec = new Integration_Log__c();
        initializeLog(logRec, 'AccountRestResource.createAccount');

        try {
            String rawBody = (RestContext.request == null || RestContext.request.requestBody == null)
                ? null
                : RestContext.request.requestBody.toString();
            logRec.Request_Body__c = rawBody;

            if (String.isBlank(rawBody)) {
                RestContext.response.statusCode = 400;

                Map<String, Object> err = new Map<String, Object>{
                    'success' => false,
                    'message' => 'Request body is required.'
                };
                String errJson = JSON.serialize(err);
                RestContext.response.responseBody = Blob.valueOf(errJson);

                logRec.Is_Error__c = true;
                logRec.Response_State__c = String.valueOf(RestContext.response.statusCode);
                logRec.Response_Body__c = errJson;
                return;
            }

            AccountWrapper payload = (AccountWrapper) JSON.deserialize(rawBody, AccountWrapper.class);
            if (payload == null || String.isBlank(payload.name)) {
                RestContext.response.statusCode = 400;

                Map<String, Object> err = new Map<String, Object>{
                    'success' => false,
                    'message' => 'Field "name" is required.'
                };
                String errJson = JSON.serialize(err);
                RestContext.response.responseBody = Blob.valueOf(errJson);

                logRec.Is_Error__c = true;
                logRec.Response_State__c = String.valueOf(RestContext.response.statusCode);
                logRec.Response_Body__c = errJson;
                return;
            }

            Account acc = new Account();
            acc.Name = payload.name;
            acc.Phone = payload.phone;
            acc.Website = payload.website;
            acc.Industry = payload.industry;
            acc.BillingCity = payload.billingCity;
            insert acc;

            Map<String, Object> resp = new Map<String, Object>{
                'success' => true,
                'accountId' => acc.Id,
                'message' => 'Account created successfully.'
            };
            String respJson = JSON.serialize(resp);

            RestContext.response.responseBody = Blob.valueOf(respJson);
            RestContext.response.statusCode = 201;

            logRec.Is_Error__c = false;
            logRec.Response_State__c = String.valueOf(RestContext.response.statusCode);
            logRec.Response_Body__c = respJson;
        } catch (Exception e) {
            RestContext.response.statusCode = 500;

            Map<String, Object> err = new Map<String, Object>{
                'success' => false,
                'message' => e.getMessage()
            };
            String errJson = JSON.serialize(err);
            RestContext.response.responseBody = Blob.valueOf(errJson);

            logRec.Is_Error__c = true;
            logRec.Exception_Message__c = e.getMessage();
            logRec.Exception_StackTrace__c = e.getStackTraceString();
            logRec.Response_State__c = String.valueOf(RestContext.response.statusCode);
            logRec.Response_Body__c = errJson;
        } finally {
            insert logRec;
        }
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

    global class AccountWrapper {
        public String name;
        public String phone;
        public String website;
        public String industry;
        public String billingCity;
    }
}
