# Agevolazioni di catalogo: Salesforce → Tableau

Aggiornamento produzione: 25 settembre 2026. Snapshot completo di `order.catalogData.seasons[].advantages[]` dal GET Catalog SecuTix. Distribuzione Salesforce `0AfSX000000q44L0AQ` (87 test completati). Le 45 definizioni includono 30 agevolazioni di tipo `CODE` e 15 di tipo `CONTACT`.

```text
Catalog_Advantage__c (45)
  Id ──< Catalog_Advantage_Product__c (207) >── Inventory__c
             Catalog_Advantage__c                 Inventory__c
```

Per Tableau, usare le **relazioni logiche** `Catalog_Advantage__c.Id = Catalog_Advantage_Product__c.Catalog_Advantage__c` e `Catalog_Advantage_Product__c.Inventory__c = Inventory__c.Id`. La grana della tabella ponte è una riga per **stagione × agevolazione × prodotto**. `Advantage_Key__c` (`Season_Id|Advantage_Id`) e `Relationship_Key__c` (`Season_Id|Advantage_Id|Product_Id`) sono chiavi esterne univoche. Tutti i 207 legami in produzione hanno un `Inventory__c` della stessa stagione; il sync non collega ID prodotto omonimi di altre stagioni.

| Oggetto | Campi principali | Uso |
| --- | --- | --- |
| `Catalog_Advantage__c` | `Advantage_Id__c`, `Season_Id__c`, `Code__c`, `State__c`, `Advantage_Type__c`, `Target_Type__c`, `Access_Code__c`, `Name_IT__c`, `Name_EN__c`, `Description_IT__c`, `Description_EN__c`, `Start__c`, `Mandatory_Contact__c`, `Exclusive__c`, `Max_Order_Quantity__c`, `Max_Quantity_Per_Performance__c`, `Contact_Limitation__c`, altri flag di idoneità, `Raw_JSON__c` | Definizione dettagliata dell’agevolazione nel catalogo. |
| `Catalog_Advantage_Product__c` | `Catalog_Advantage__c`, `Inventory__c`, `Product_Id__c`, `Product_Code__c`, `Season_Id__c`, `Sequence__c` | Tabella ponte prodotto/agevolazione. |
| `Inventory__c` | `Inventory_Id__c`, `Season_Id__c`, `Product_Advantages__c` | Dimensione prodotto corrente; il JSON storico resta disponibile nel layout. |

`Account.Advantages__c` e `Account.Has_Advantages__c` descrivono invece le agevolazioni del contatto provenienti dal webhook SecuTix. Non esiste qui un collegamento verificato tra agevolazione sul contatto, ordine e sconto effettivamente applicato. Non usare la relazione catalogo come prova dell’utilizzo dello sconto.

Il precedente [export `product-advantages.csv`](product-advantages.csv) deriva dal JSON condensato di `Inventory__c.Product_Advantages__c` e rappresenta un’altra fotografia (141 occorrenze, 39 ID distinti al momento dell’estrazione). Lo snapshot GET Catalog completo ora fornisce 45 definizioni per stagione e 207 legami con i relativi dettagli. Per nuovi report usare gli oggetti relazionali; tenere l’export precedente come confronto storico, senza unire i conteggi.

Nel payload attuale tutti i 45 nomi italiani sono presenti, mentre nomi inglesi e descrizioni non sono valorizzati dal fornitore. `Access_Code__c` è presente per 30 agevolazioni e `Start__c` per 9: i campi vuoti riflettono il sorgente.

La sincronizzazione ripetibile è [`scripts/catalog/sync_advantages_to_salesforce.py`](../../scripts/catalog/sync_advantages_to_salesforce.py). Senza `--execute` fa solo il controllo dello snapshot. L’upsert aggiorna le chiavi presenti e non cancella quelle scomparse dal catalogo; una rimozione richiede una revisione separata per non eliminare dati storici. I dettagli non si aggiornano automaticamente al successivo GET Catalog: ripetere lo script con uno snapshot completo e verificato quando il catalogo cambia.
