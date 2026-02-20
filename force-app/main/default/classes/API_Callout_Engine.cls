public without sharing class API_Callout_Engine {

    private static final Boolean isSandBox = isSandbox();

    public class Result {
        public Object payload;
        public List<Integration_Log__c> integrationLogs;

        public Result() {
            this.payload = null;
            this.integrationLogs = new List<Integration_Log__c>();
        }
    }

    public static Object callApi(String apiName, Object request){
        Result result = callApi(apiName, request, true);
        return result.payload;
    }

    public static Result callApi(String apiName, Object request, Boolean insertLog) {
        System.debug('** Callout_Engine.callApi start **');
        System.debug('** Input apiName: ' + apiName + ' **');
        System.debug('** Input request: ' + request + ' **');

        Result result = new Result();
        Integration_Log__c logRow;
        String respJson;

        try {
            // Retrieve Config, Create Log
            Integration_Configuration__c config = Integration_Configuration__c.getValues(apiName);
            String reqJson = JSON.serialize(request);

            System.debug('Request after serialization :::'+reqJson);

            logRow = new Integration_Log__c(
                    Flow_Name__c = apiName,
                    Integration_Type__c = 'Outbound',
                    Request_Body__c = reqJson.abbreviate(131072)
            );

            if(config == null){
                logRow.Is_Error__c = true;
                logRow.Response_Body__c = 'ERROR: The system could not find an Integration_Configuration__c custom setting record having name ' + apiName;

                if(insertLog) {
                    insert logRow;
                }

                result.integrationLogs.add(logRow);
                result.payload = null;
                return result;
            }

            System.debug('config: '+config);

            // Make HTTP request
            HttpRequest req = new HttpRequest();
            if(isSandBox) {
                req.setEndpoint('callout:' + config.Named_Credential_Sandbox__c + '' + config.Endpoint_Path__c);
            }
            else {
                req.setEndpoint('callout:' + config.Named_Credential_Prod__c + '' + config.Endpoint_Path__c);
            }

            // Determine Content-Type based on checkbox fields
            String contentType = 'application/json'; // Default
            Boolean isJson = config.Content_Type_JSON__c != null ? config.Content_Type_JSON__c : false;
            Boolean isEncoded = config.Content_Type_Encoded__c != null ? config.Content_Type_Encoded__c : false;

            // If only Content_Type_Encoded is true, use URL-encoded
            if(!isJson && isEncoded) {
                contentType = 'application/x-www-form-urlencoded';
            }
            // If both are true, none are true, or only JSON is true: use JSON (priority)
            else {
                contentType = 'application/json';
            }

            req.setHeader('Content-Type', contentType);
            req.setMethod(config.HTTP_Method__c);
            if(config.HTTP_Method__c != 'GET') {
                // Convert to URL-encoded format if Content-Type requires it
                if(contentType == 'application/x-www-form-urlencoded') {
                    String urlEncodedBody = convertJsonToUrlEncoded(reqJson);
                    req.setBody(urlEncodedBody);
                } else {
                    req.setBody(reqJson);
                }
            }

            req.setTimeout(Integer.valueOf(config.Timeout__c));
            Http http = new Http();
            HttpResponse res;

            Long timestampCallout = DateTime.now().getTime();

            if(!config.Use_Mock__c) {
                res = http.send(req);
            }
            // else {
            //     Type mockClass = Type.forName('API_Mock.' + config.Mock_Apex_Class__c);
            //     System.debug('Mock class name : '+mockClass);
            //     API_Mock mockService = (API_Mock) mockClass.newInstance();
            //     res = mockService.respond(req);
            // }

            
            Long timestampResponseReceived = DateTime.now().getTime();

            String elapsedTime = 'Timestamp invio richiesta: '+String.valueOf(timestampCallout)+' ; Timestamp ricezione risposta: '+String.valueOf(timestampResponseReceived)+' ; ';
            elapsedTime += 'ELAPSED TIME: '+String.valueOf(timestampResponseReceived-timestampCallout)+' ms .';

            System.debug(' Response before serialization :::'+res);

            // Sanitize response to avoid invalid control chars (e.g., unescaped tabs) before JSON deserialization.
            respJson = sanitizeJson(res.getBody());

            // Get HTTP response
            Type respClass = Type.forName(config.Response_Wrapper_Class__c);
            Object responseWrapper = respClass.newInstance();
            System.debug('** respJson: ' + respJson);
            System.debug('** respClass: ' + respClass);
            responseWrapper = JSON.deserialize(respJson, respClass);
            System.debug('** respWrapper: ' + responseWrapper);

            logRow.Response_State__c = String.valueOf(res.getStatusCode());
            logRow.Response_Body__c = (elapsedTime+'************'+respJson).abbreviate(131072);
            logRow.Request_Endpoint__c = req.getEndpoint();
            logRow.Request_Headers__c = req.getHeader('Content-Type');

            if(insertLog) {
                insert logRow;
            }

            result.integrationLogs.add(logRow);
            result.payload = responseWrapper;
            return result;
        }
        catch (Exception e) {
            logRow = new Integration_Log__c(
                    Flow_Name__c = apiName,
                    Integration_Type__c = 'Outbound',
                    Request_Body__c = JSON.serialize(request).abbreviate(131072),
                    Is_Error__c = true,
                    Response_Body__c = (respJson)?.abbreviate(131072),
                    Exception_Message__c = (e.getTypeName() + '\n' + e.getMessage()).abbreviate(131072),
                    Exception_StackTrace__c = (e.getStackTraceString()).abbreviate(131072)
            );

            if(insertLog) {
                insert logRow;
            }

            result.integrationLogs.add(logRow);
            result.payload = null;
            return result;
        }
    }

    public static Boolean isSandBox() {
		return [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
    }

    private static String convertJsonToUrlEncoded(String jsonString) {
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonString);
        List<String> params = new List<String>();

        for(String key : jsonMap.keySet()) {
            Object value = jsonMap.get(key);
            if(value != null) {
                params.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + EncodingUtil.urlEncode(String.valueOf(value), 'UTF-8'));
            }
        }

        return String.join(params, '&');
    }

    // Removes ASCII control characters that would break JSON.parse (e.g., unescaped tabs).
    private static String sanitizeJson(String raw) {
        if (raw == null) {
            return null;
        }
        // Keep standard printable characters; strip 0x00-0x1F except LF/CR if present.
        String cleaned = raw.replaceAll('[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]', '');
        return cleaned;
    }
}