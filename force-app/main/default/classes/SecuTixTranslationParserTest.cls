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

    @IsTest
    static void convertsHtmlToReadablePlainText() {
        String html = '<script>alert("ignored")</script>' +
            '<p>Prima&nbsp;<strong>riga</strong></p>' +
            '<ul><li>Voce &amp; dettagli</li><li>Seconda voce</li></ul>' +
            '<div>Finale<br/>Riga</div>';

        System.assertEquals(
            'Prima riga\n- Voce & dettagli\n- Seconda voce\nFinale\nRiga',
            SecuTixTranslationParser.plainText(html, 32768)
        );
        System.assertEquals('12345', SecuTixTranslationParser.plainText('<b>123456</b>', 5));
        System.assertEquals(null, SecuTixTranslationParser.plainText('<p>&nbsp;</p>', 255));
    }
}
