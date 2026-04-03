/**
 * @description Test class for GlobalIdService. Covers generation format, validation
 *              of valid and invalid IDs, region extraction, and null/edge-case handling.
 * @group Core
 */
@IsTest
private class GlobalIdServiceTest {

    @IsTest
    static void testGenerate_ReturnsCorrectFormat() {
        String globalId = GlobalIdService.generate('EU');

        System.assertNotEquals(null, globalId, 'Generated ID should not be null');
        System.assert(globalId.startsWith('GBL-EU-'), 'ID should start with GBL-EU-. Got: ' + globalId);
        System.assertEquals(18, globalId.length(), 'GBL-EU-00000001 should be 18 characters');
        System.assert(
            GlobalIdService.isValid(globalId),
            'Generated ID should pass validation. Got: ' + globalId
        );
    }

    @IsTest
    static void testGenerate_IncrementsSequence() {
        Account acc = new Account(
            Name = 'Test Account',
            Global_Customer_ID__c = 'GBL-US-00000005'
        );
        insert acc;

        String newId = GlobalIdService.generate('US');

        System.assertEquals('GBL-US-00000006', newId, 'Should increment from existing max sequence');
    }

    @IsTest
    static void testGenerate_StartsAtOneWhenNoExisting() {
        String globalId = GlobalIdService.generate('APAC');

        System.assertEquals('GBL-APAC-00000001', globalId, 'Should start at sequence 1 when no records exist');
    }

    @IsTest
    static void testGenerate_NullRegionThrowsException() {
        try {
            GlobalIdService.generate(null);
            System.assert(false, 'Should have thrown IllegalArgumentException for null region');
        } catch (IllegalArgumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('null or blank'),
                'Exception message should mention null or blank. Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void testGenerate_BlankRegionThrowsException() {
        try {
            GlobalIdService.generate('  ');
            System.assert(false, 'Should have thrown IllegalArgumentException for blank region');
        } catch (IllegalArgumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('null or blank'),
                'Exception message should mention null or blank'
            );
        }
    }

    @IsTest
    static void testGenerate_InvalidRegionThrowsException() {
        try {
            GlobalIdService.generate('TOOLONG');
            System.assert(false, 'Should have thrown IllegalArgumentException for region > 4 chars');
        } catch (IllegalArgumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('2-4 character'),
                'Exception should mention 2-4 character requirement'
            );
        }
    }

    @IsTest
    static void testGenerate_SingleCharRegionThrowsException() {
        try {
            GlobalIdService.generate('A');
            System.assert(false, 'Should have thrown IllegalArgumentException for 1-char region');
        } catch (IllegalArgumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('2-4 character'),
                'Exception should mention 2-4 character requirement'
            );
        }
    }

    @IsTest
    static void testGenerate_LowercaseRegionIsNormalized() {
        String globalId = GlobalIdService.generate('eu');

        System.assert(
            globalId.startsWith('GBL-EU-'),
            'Lowercase region should be uppercased. Got: ' + globalId
        );
    }

    @IsTest
    static void testIsValid_ValidIds() {
        System.assertEquals(true, GlobalIdService.isValid('GBL-EU-00000001'), 'Standard EU ID should be valid');
        System.assertEquals(true, GlobalIdService.isValid('GBL-US-99999999'), 'Max sequence should be valid');
        System.assertEquals(true, GlobalIdService.isValid('GBL-APAC-00000001'), 'Four-char region should be valid');
        System.assertEquals(true, GlobalIdService.isValid('GBL-UK-00000100'), 'Two-char region should be valid');
    }

    @IsTest
    static void testIsValid_InvalidIds() {
        System.assertEquals(false, GlobalIdService.isValid(null), 'Null should be invalid');
        System.assertEquals(false, GlobalIdService.isValid(''), 'Empty string should be invalid');
        System.assertEquals(false, GlobalIdService.isValid('  '), 'Blank string should be invalid');
        System.assertEquals(false, GlobalIdService.isValid('GBL-E-00000001'), 'Single-char region should be invalid');
        System.assertEquals(false, GlobalIdService.isValid('GBL-TOOLONG-00000001'), 'Region > 4 chars should be invalid');
        System.assertEquals(false, GlobalIdService.isValid('GBL-EU-0000001'), 'Sequence < 8 digits should be invalid');
        System.assertEquals(false, GlobalIdService.isValid('GBL-EU-000000001'), 'Sequence > 8 digits should be invalid');
        System.assertEquals(false, GlobalIdService.isValid('XXX-EU-00000001'), 'Wrong prefix should be invalid');
        System.assertEquals(false, GlobalIdService.isValid('GBL-12-00000001'), 'Numeric region should be invalid');
        System.assertEquals(false, GlobalIdService.isValid('GBL-eu-00000001'), 'Lowercase region should be invalid');
        System.assertEquals(false, GlobalIdService.isValid('GBLEU00000001'), 'Missing separators should be invalid');
    }

    @IsTest
    static void testExtractRegion_ValidIds() {
        System.assertEquals('EU', GlobalIdService.extractRegion('GBL-EU-00000001'), 'Should extract EU');
        System.assertEquals('US', GlobalIdService.extractRegion('GBL-US-99999999'), 'Should extract US');
        System.assertEquals('APAC', GlobalIdService.extractRegion('GBL-APAC-00000001'), 'Should extract APAC');
    }

    @IsTest
    static void testExtractRegion_NullThrowsException() {
        try {
            GlobalIdService.extractRegion(null);
            System.assert(false, 'Should have thrown IllegalArgumentException for null');
        } catch (IllegalArgumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('invalid'),
                'Exception should mention invalid ID'
            );
        }
    }

    @IsTest
    static void testExtractRegion_InvalidIdThrowsException() {
        try {
            GlobalIdService.extractRegion('NOT-A-VALID-ID');
            System.assert(false, 'Should have thrown IllegalArgumentException for invalid ID');
        } catch (IllegalArgumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('invalid'),
                'Exception should mention invalid ID'
            );
        }
    }
}
