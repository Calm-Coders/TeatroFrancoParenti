public class SecuTixTranslationParser {
    public static String italianOrEnglish(Object rawValue, Integer maxLength) {
        String value = translatedValue(rawValue, 'it');
        if (String.isBlank(value)) {
            value = translatedValue(rawValue, 'en');
        }
        if (String.isBlank(value) && rawValue instanceof String) {
            value = String.valueOf(rawValue);
        }
        if (String.isBlank(value)) {
            return null;
        }
        return maxLength != null && maxLength > 0 && value.length() > maxLength
            ? value.substring(0, maxLength)
            : value;
    }

    private static String translatedValue(Object rawValue, String locale) {
        if (rawValue == null || String.isBlank(locale)) {
            return null;
        }

        Object translations = rawValue;
        if (rawValue instanceof Map<String, Object>) {
            Map<String, Object> wrapper = (Map<String, Object>) rawValue;
            if (wrapper.containsKey('translations')) {
                translations = wrapper.get('translations');
            }
        }

        if (translations instanceof Map<String, Object>) {
            Map<String, Object> translationsByLocale = (Map<String, Object>) translations;
            String directValue = asString(translationsByLocale.get(locale));
            if (!String.isBlank(directValue)) {
                return directValue;
            }
            String itemLocale = asString(translationsByLocale.get('locale'));
            String itemValue = asString(translationsByLocale.get('value'));
            return locale.equalsIgnoreCase(itemLocale) && !String.isBlank(itemValue)
                ? itemValue
                : null;
        }

        if (translations instanceof List<Object>) {
            for (Object rawTranslation : (List<Object>) translations) {
                if (!(rawTranslation instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> translation = (Map<String, Object>) rawTranslation;
                String itemLocale = asString(translation.get('locale'));
                String itemValue = asString(translation.get('value'));
                if (locale.equalsIgnoreCase(itemLocale) && !String.isBlank(itemValue)) {
                    return itemValue;
                }
            }
        }
        return null;
    }

    private static String asString(Object value) {
        return value == null ? null : String.valueOf(value);
    }
}
