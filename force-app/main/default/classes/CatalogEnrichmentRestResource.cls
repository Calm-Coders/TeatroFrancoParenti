@RestResource(urlMapping='/v1/catalog-enrichment')
global without sharing class CatalogEnrichmentRestResource {
    private static final Integer LOG_LIMIT = 131072;
    private static final String FLOW_NAME = 'CatalogEnrichmentRestResource.apply';

    @HttpPost
    global static void applyEnrichment() {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }
        Integration_Log__c logRecord = new Integration_Log__c(
            Flow_Name__c = FLOW_NAME,
            Integration_Type__c = 'Inbound',
            Request_Endpoint__c = RestContext.request == null ? null : RestContext.request.resourcePath
        );
        try {
            String body = RestContext.request == null || RestContext.request.requestBody == null
                ? null
                : RestContext.request.requestBody.toString();
            logRecord.Request_Body__c = trimLog(body);
            if (String.isBlank(body)) {
                setResponse(400, new Map<String, Object>{ 'success' => false, 'message' => 'Request body is required.' }, logRecord);
                return;
            }
            Object rawPayload = JSON.deserializeUntyped(body);
            if (!(rawPayload instanceof Map<String, Object>)) {
                setResponse(400, new Map<String, Object>{ 'success' => false, 'message' => 'Request body must be a JSON object.' }, logRecord);
                return;
            }
            CatalogEnrichmentService.Result applyResult = CatalogEnrichmentService.applyResponse(
                (Map<String, Object>) rawPayload
            );
            Map<String, Object> responsePayload = applyResult.toMap();
            responsePayload.put('success', applyResult.errors.isEmpty());
            setResponse(applyResult.errors.isEmpty() ? 200 : 207, responsePayload, logRecord);
        } catch (JSONException error) {
            setException(logRecord, error);
            setResponse(400, new Map<String, Object>{ 'success' => false, 'message' => 'Invalid JSON payload.' }, logRecord);
        } catch (Exception error) {
            setException(logRecord, error);
            setResponse(500, new Map<String, Object>{ 'success' => false, 'message' => error.getMessage() }, logRecord);
        } finally {
            insert logRecord;
        }
    }

    private static void setResponse(Integer statusCode, Map<String, Object> payload, Integration_Log__c logRecord) {
        String responseBody = JSON.serialize(payload);
        RestContext.response.statusCode = statusCode;
        RestContext.response.responseBody = Blob.valueOf(responseBody);
        logRecord.Response_State__c = String.valueOf(statusCode);
        logRecord.Response_Body__c = trimLog(responseBody);
        logRecord.Is_Error__c = statusCode >= 400;
    }

    private static void setException(Integration_Log__c logRecord, Exception error) {
        logRecord.Exception_Message__c = trimLog(error.getMessage());
        logRecord.Exception_StackTrace__c = trimLog(error.getStackTraceString());
    }

    private static String trimLog(String value) {
        return value == null ? null : value.abbreviate(LOG_LIMIT);
    }
}
