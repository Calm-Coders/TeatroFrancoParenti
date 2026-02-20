global virtual class API_Mock implements HttpCalloutMock {
    global virtual HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody('{"example":"test"}');
        res.setStatusCode(200);
        return res;
    }

    //Example
    // global class VoucherMock extends API_Mock {
    //     global override HttpResponse respond(HttpRequest req) {
    //         HttpResponse res = new HttpResponse();
    //         res.setHeader('Content-Type', 'application/json');
    //         res.setStatusCode(200);

    //         Integration_Configuration__c config = Integration_Configuration__c.getValues('Voucher');

    //         // Switch for different Mocked Response Body scenarios
    //         Integer scenario = config.Mock_API_Scenario__c != null ? (Integer) config.Mock_API_Scenario__c : 0;
    //         switch on scenario{
    //             // happy scenario  - RISPOSTA OK
    //             when 0 {
    //                 String body = '{"code":"BDAY202529347","errore":""}';
    //                 res.setBody(body);
    //             }
    //             // ERROR scenario
    //             when 1 {
    //                 String body = '{"code":"","errore":"il codice del voucher \u00e8 gi\u00e0 presente"}';
    //                 res.setBody(body);
    //             }
    //         }        
    //         return res;
    //     }
    // }
}