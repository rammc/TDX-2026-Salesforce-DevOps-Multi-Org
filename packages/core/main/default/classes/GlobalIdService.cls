/**
 * @description Service class for generating and validating global customer IDs.
 *              IDs follow the format GBL-{region}-{sequence} where region is a 2-4
 *              character code (e.g. EU, US, APAC) and sequence is a zero-padded
 *              8-digit number.
 * @group Core
 */
public with sharing class GlobalIdService {

    private static final String PREFIX = 'GBL';
    private static final String SEPARATOR = '-';
    private static final Integer SEQUENCE_LENGTH = 8;
    private static final Pattern GLOBAL_ID_PATTERN = Pattern.compile(
        '^GBL-[A-Z]{2,4}-\\d{' + SEQUENCE_LENGTH + '}$'
    );

    /**
     * @description Generates a new global customer ID for the given region.
     *              Uses a counter approach by querying for the maximum existing
     *              sequence number in the specified region and incrementing it.
     * @param region A 2-4 character uppercase region code (e.g. EU, US, APAC)
     * @return A new global customer ID in format GBL-{region}-{sequence}
     * @throws IllegalArgumentException if region is null, blank, or invalid format
     */
    public static String generate(String region) {
        if (String.isBlank(region)) {
            throw new IllegalArgumentException('Region must not be null or blank.');
        }

        region = region.toUpperCase().trim();

        if (!Pattern.matches('^[A-Z]{2,4}$', region)) {
            throw new IllegalArgumentException(
                'Region must be a 2-4 character alphabetic code. Received: ' + region
            );
        }

        String likePattern = PREFIX + SEPARATOR + region + SEPARATOR + '%';

        List<Account> existing = [
            SELECT Global_Customer_ID__c
            FROM Account
            WHERE Global_Customer_ID__c LIKE :likePattern
            ORDER BY Global_Customer_ID__c DESC
            LIMIT 1
        ];

        Integer nextSequence = 1;

        if (!existing.isEmpty()) {
            String lastId = existing[0].Global_Customer_ID__c;
            String sequencePart = lastId.substringAfterLast(SEPARATOR);
            nextSequence = Integer.valueOf(sequencePart) + 1;
        }

        String sequenceStr = String.valueOf(nextSequence).leftPad(SEQUENCE_LENGTH, '0');

        return PREFIX + SEPARATOR + region + SEPARATOR + sequenceStr;
    }

    /**
     * @description Validates whether a given string matches the global customer ID format.
     * @param globalId The string to validate
     * @return true if the string matches GBL-{region}-{sequence} format, false otherwise
     */
    public static Boolean isValid(String globalId) {
        if (String.isBlank(globalId)) {
            return false;
        }
        Matcher m = GLOBAL_ID_PATTERN.matcher(globalId);
        return m.matches();
    }

    /**
     * @description Extracts the region code from a valid global customer ID.
     * @param globalId A global customer ID in format GBL-{region}-{sequence}
     * @return The region code (e.g. EU, US, APAC)
     * @throws IllegalArgumentException if the globalId is null or invalid format
     */
    public static String extractRegion(String globalId) {
        if (!isValid(globalId)) {
            throw new IllegalArgumentException(
                'Cannot extract region from invalid Global ID: ' + globalId
            );
        }

        String[] parts = globalId.split(SEPARATOR);
        return parts[1];
    }
}
