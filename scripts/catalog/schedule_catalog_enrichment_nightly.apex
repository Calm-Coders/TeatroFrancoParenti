String jobId = System.schedule(
    'TFP Catalog Enrichment Nightly',
    '0 0 2 * * ?',
    new CatalogEnrichmentRetryScheduler()
);
System.debug('Scheduled job: ' + jobId);
