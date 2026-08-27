public without sharing class CatalogEnrichmentQueueable implements Queueable, Database.AllowsCallouts {
    private static final Integer API_BATCH_SIZE = 50;
    private static final Integer DEFAULT_TIMEOUT = 120000;
    private static final Integer LOG_LIMIT = 131072;
    private static final String FLOW_NAME = 'CatalogEnrichmentQueueable.resolveProducts';

    private List<Long> productIds;
    private Boolean forceRefresh;

    public CatalogEnrichmentQueueable(List<Long> productIds, Boolean forceRefresh) {
        Set<Long> deduped = new Set<Long>();
        if (productIds != null) {
            deduped.addAll(productIds);
            deduped.remove(null);
        }
        this.productIds = new List<Long>(deduped);
        this.productIds.sort();
        this.forceRefresh = forceRefresh == true;
    }

    public void execute(QueueableContext context) {
        if (productIds.isEmpty()) {
            return;
        }
        Catalog_Enrichment_Setting__c setting = Catalog_Enrichment_Setting__c.getOrgDefaults();
        if (!isConfigured(setting)) {
            return;
        }

        List<Long> currentBatch = new List<Long>();
        List<Long> remaining = new List<Long>();
        for (Integer index = 0; index < productIds.size(); index++) {
            if (index < API_BATCH_SIZE) {
                currentBatch.add(productIds[index]);
            } else {
                remaining.add(productIds[index]);
            }
        }

        Map<String, Object> requestPayload = new Map<String, Object>{ 'productIds' => currentBatch };
        if (forceRefresh) {
            requestPayload.put('forceRefresh', true);
        }
        String requestBody = JSON.serialize(requestPayload);
        Integration_Log__c logRecord = new Integration_Log__c(
            Flow_Name__c = FLOW_NAME,
            Integration_Type__c = 'Outbound',
            Request_Body__c = trimLog(requestBody)
        );
        Boolean completedSuccessfully = false;

        try {
            HttpRequest request = new HttpRequest();
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setEndpoint('callout:' + setting.Named_Credential__c + normalizePath(setting.Endpoint_Path__c));
            request.setTimeout(setting.Timeout_Milliseconds__c == null
                ? DEFAULT_TIMEOUT
                : setting.Timeout_Milliseconds__c.intValue());
            request.setBody(requestBody);

            HttpResponse response = new Http().send(request);
            logRecord.Request_Endpoint__c = request.getEndpoint();
            logRecord.Request_Headers__c = 'Content-Type: application/json';
            logRecord.Response_State__c = String.valueOf(response.getStatusCode());
            logRecord.Response_Body__c = trimLog(response.getBody());
            if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
                throw new CatalogCalloutException(
                    'Catalog resolve returned HTTP ' + response.getStatusCode() + ': ' + response.getBody()
                );
            }

            Object rawResponse = JSON.deserializeUntyped(response.getBody());
            if (!(rawResponse instanceof Map<String, Object>)) {
                throw new CatalogCalloutException('Catalog resolve returned a non-object response.');
            }
            CatalogEnrichmentService.Result applyResult = CatalogEnrichmentService.applyResponse(
                (Map<String, Object>) rawResponse
            );
            logRecord.Is_Error__c = !applyResult.errors.isEmpty();
            if (!applyResult.errors.isEmpty()) {
                logRecord.Exception_Message__c = trimLog(String.join(applyResult.errors, '\n'));
            }
            completedSuccessfully = true;
        } catch (Exception error) {
            logRecord.Is_Error__c = true;
            logRecord.Exception_Message__c = trimLog(error.getTypeName() + ': ' + error.getMessage());
            logRecord.Exception_StackTrace__c = trimLog(error.getStackTraceString());
            CatalogEnrichmentService.markError(currentBatch, error.getMessage());
        } finally {
            insert logRecord;
        }

        if (completedSuccessfully && !remaining.isEmpty()) {
            System.enqueueJob(new CatalogEnrichmentQueueable(remaining, forceRefresh));
        }
    }

    public static Id enqueueIfConfigured(List<Long> productIds, Boolean forceRefresh) {
        try {
            Catalog_Enrichment_Setting__c setting = Catalog_Enrichment_Setting__c.getOrgDefaults();
            if (!isConfigured(setting) || productIds == null || productIds.isEmpty()) {
                return null;
            }
            return System.enqueueJob(new CatalogEnrichmentQueueable(productIds, forceRefresh));
        } catch (Exception error) {
            try {
                insert new Integration_Log__c(
                    Flow_Name__c = FLOW_NAME,
                    Integration_Type__c = 'Outbound',
                    Is_Error__c = true,
                    Exception_Message__c = trimLog(error.getMessage()),
                    Exception_StackTrace__c = trimLog(error.getStackTraceString())
                );
            } catch (Exception ignored) {
                // Enrichment must never make the inventory webhook fail.
            }
            return null;
        }
    }

    public static Boolean isConfigured() {
        return isConfigured(Catalog_Enrichment_Setting__c.getOrgDefaults());
    }

    private static Boolean isConfigured(Catalog_Enrichment_Setting__c setting) {
        return setting != null && setting.Enabled__c == true && !String.isBlank(setting.Named_Credential__c);
    }

    private static String normalizePath(String path) {
        if (String.isBlank(path)) {
            return '/catalog/products/resolve';
        }
        return path.startsWith('/') ? path : '/' + path;
    }

    private static String trimLog(String value) {
        return value == null ? null : value.abbreviate(LOG_LIMIT);
    }

    public class CatalogCalloutException extends Exception {
    }
}
