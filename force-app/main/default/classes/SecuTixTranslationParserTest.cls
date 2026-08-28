@IsTest
private class SecuTixTranslationParserTest {
    @IsTest
    static void parsesSupportedTranslationShapesAndFallbacks() {
        Object wrapperList = JSON.deserializeUntyped(
            '{"translations":[{"locale":"it","value":"Italiano"},{"locale":"en","value":"English"}]}'
        );
        Object englishOnly = JSON.deserializeUntyped(
            '{"translations":[{"locale":"it","value":null},{"locale":"en","value":"English"}]}'
        );
        Object directMap = JSON.deserializeUntyped('{"it":"Diretto","en":"Direct"}');
        Object wrapperMap = JSON.deserializeUntyped('{"translations":{"en":"Mapped English"}}');
        Object emptyTranslations = JSON.deserializeUntyped(
            '{"translations":[{"locale":"it","value":null},{"locale":"en","value":null}]}'
        );

        System.assertEquals('Italiano', SecuTixTranslationParser.italianOrEnglish(wrapperList, 255));
        System.assertEquals('English', SecuTixTranslationParser.italianOrEnglish(englishOnly, 255));
        System.assertEquals('Diretto', SecuTixTranslationParser.italianOrEnglish(directMap, 255));
        System.assertEquals('Mapped English', SecuTixTranslationParser.italianOrEnglish(wrapperMap, 255));
        System.assertEquals('Plain text', SecuTixTranslationParser.italianOrEnglish('Plain text', 255));
        System.assertEquals(null, SecuTixTranslationParser.italianOrEnglish(emptyTranslations, 255));
        System.assertEquals('12345', SecuTixTranslationParser.italianOrEnglish('123456789', 5));
    }
}
