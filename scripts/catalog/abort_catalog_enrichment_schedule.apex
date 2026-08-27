for (CronTrigger triggerRecord : [
    SELECT Id
    FROM CronTrigger
    WHERE CronJobDetail.Name = 'TFP Catalog Enrichment Nightly'
]) {
    System.abortJob(triggerRecord.Id);
}
