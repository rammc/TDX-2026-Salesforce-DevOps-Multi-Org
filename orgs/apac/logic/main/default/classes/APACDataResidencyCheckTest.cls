/**
 * @description Test class for APACDataResidencyCheck. Validates APAC resident
 *              detection, residency enforcement for restricted accounts, and
 *              completeness of the APAC country list.
 * @group APAC Compliance
 */
@IsTest
private class APACDataResidencyCheckTest {

    @TestSetup
    static void setupTestData() {
        List<Account> accounts = new List<Account>();

        accounts.add(new Account(
            Name = 'Sydney Corp',
            BillingCountry = 'Australia',
            modbp__Data_Classification__c = 'Restricted'
        ));
        accounts.add(new Account(
            Name = 'Tokyo Inc',
            BillingCountry = 'Japan',
            modbp__Data_Classification__c = 'Public'
        ));
        accounts.add(new Account(
            Name = 'Singapore Ltd',
            BillingCountry = 'Singapore',
            modbp__Data_Classification__c = 'Restricted'
        ));
        accounts.add(new Account(
            Name = 'Berlin GmbH',
            BillingCountry = 'Germany',
            modbp__Data_Classification__c = 'Restricted'
        ));
        accounts.add(new Account(
            Name = 'New York LLC',
            BillingCountry = 'United States',
            modbp__Data_Classification__c = 'Public'
        ));
        accounts.add(new Account(
            Name = 'No Country Account',
            BillingCountry = null,
            modbp__Data_Classification__c = 'Restricted'
        ));
        accounts.add(new Account(
            Name = 'Mumbai Pvt Ltd',
            BillingCountry = 'India',
            modbp__Data_Classification__c = 'Confidential'
        ));
        accounts.add(new Account(
            Name = 'Seoul Corp',
            BillingCountry = 'South Korea',
            modbp__Data_Classification__c = 'Internal'
        ));

        insert accounts;
    }

    @IsTest
    static void testIsAPACResident_AustralianAccount() {
        Account acc = [
            SELECT Name, BillingCountry, modbp__Data_Classification__c
            FROM Account
            WHERE Name = 'Sydney Corp'
            LIMIT 1
        ];

        Test.startTest();
        Boolean result = APACDataResidencyCheck.isAPACResident(acc);
        Test.stopTest();

        System.assertEquals(true, result, 'Australian account should be identified as APAC resident.');
    }

    @IsTest
    static void testIsAPACResident_JapaneseAccount() {
        Account acc = [
            SELECT Name, BillingCountry, modbp__Data_Classification__c
            FROM Account
            WHERE Name = 'Tokyo Inc'
            LIMIT 1
        ];

        Test.startTest();
        Boolean result = APACDataResidencyCheck.isAPACResident(acc);
        Test.stopTest();

        System.assertEquals(true, result, 'Japanese account should be identified as APAC resident.');
    }

    @IsTest
    static void testIsAPACResident_NonAPACAccount() {
        Account acc = [
            SELECT Name, BillingCountry, modbp__Data_Classification__c
            FROM Account
            WHERE Name = 'Berlin GmbH'
            LIMIT 1
        ];

        Test.startTest();
        Boolean result = APACDataResidencyCheck.isAPACResident(acc);
        Test.stopTest();

        System.assertEquals(false, result, 'German account should not be identified as APAC resident.');
    }

    @IsTest
    static void testIsAPACResident_NullBillingCountry() {
        Account acc = [
            SELECT Name, BillingCountry, modbp__Data_Classification__c
            FROM Account
            WHERE Name = 'No Country Account'
            LIMIT 1
        ];

        Test.startTest();
        Boolean result = APACDataResidencyCheck.isAPACResident(acc);
        Test.stopTest();

        System.assertEquals(false, result, 'Account with null BillingCountry should not be APAC resident.');
    }

    @IsTest
    static void testIsAPACResident_NullAccount() {
        Test.startTest();
        try {
            APACDataResidencyCheck.isAPACResident(null);
            System.assert(false, 'Expected APACDataResidencyException for null account.');
        } catch (APACDataResidencyCheck.APACDataResidencyException e) {
            System.assert(e.getMessage().contains('cannot be null'),
                'Exception message should indicate null account.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testEnforceResidency_AllAPACRestricted() {
        List<Account> apacRestricted = [
            SELECT Name, BillingCountry, modbp__Data_Classification__c
            FROM Account
            WHERE modbp__Data_Classification__c = 'Restricted'
              AND BillingCountry IN ('Australia', 'Japan', 'Singapore', 'India', 'South Korea')
        ];

        Test.startTest();
        try {
            APACDataResidencyCheck.enforceResidency(apacRestricted);
            System.assert(true, 'All APAC restricted accounts should pass residency check.');
        } catch (APACDataResidencyCheck.APACDataResidencyException e) {
            System.assert(false, 'Should not throw for APAC restricted accounts: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testEnforceResidency_NonAPACRestrictedFails() {
        List<Account> mixedAccounts = [
            SELECT Name, BillingCountry, modbp__Data_Classification__c
            FROM Account
            WHERE modbp__Data_Classification__c = 'Restricted'
        ];

        Test.startTest();
        try {
            APACDataResidencyCheck.enforceResidency(mixedAccounts);
            System.assert(false, 'Expected APACDataResidencyException for non-APAC restricted accounts.');
        } catch (APACDataResidencyCheck.APACDataResidencyException e) {
            System.assert(
                e.getMessage().contains('Data residency violation'),
                'Exception should reference data residency violation.'
            );
            System.assert(
                e.getMessage().contains('Berlin GmbH') || e.getMessage().contains('No Country Account'),
                'Exception should reference the violating account.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testEnforceResidency_NonRestrictedNonAPACPasses() {
        List<Account> nonRestricted = [
            SELECT Name, BillingCountry, modbp__Data_Classification__c
            FROM Account
            WHERE modbp__Data_Classification__c != 'Restricted'
        ];

        Test.startTest();
        try {
            APACDataResidencyCheck.enforceResidency(nonRestricted);
            System.assert(true, 'Non-restricted accounts should pass regardless of country.');
        } catch (APACDataResidencyCheck.APACDataResidencyException e) {
            System.assert(false, 'Non-restricted accounts should not trigger residency violations.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testEnforceResidency_EmptyAndNullLists() {
        Test.startTest();
        APACDataResidencyCheck.enforceResidency(new List<Account>());
        APACDataResidencyCheck.enforceResidency(null);
        Test.stopTest();

        System.assert(true, 'Empty or null list should not throw.');
    }

    @IsTest
    static void testGetAPACCountries_Completeness() {
        Test.startTest();
        Set<String> countries = APACDataResidencyCheck.getAPACCountries();
        Test.stopTest();

        System.assert(!countries.isEmpty(), 'APAC countries set should not be empty.');
        System.assert(countries.contains('Australia'), 'Should contain Australia.');
        System.assert(countries.contains('Japan'), 'Should contain Japan.');
        System.assert(countries.contains('Singapore'), 'Should contain Singapore.');
        System.assert(countries.contains('India'), 'Should contain India.');
        System.assert(countries.contains('New Zealand'), 'Should contain New Zealand.');
        System.assert(countries.contains('South Korea'), 'Should contain South Korea.');
        System.assert(countries.contains('China'), 'Should contain China.');
        System.assert(countries.contains('Indonesia'), 'Should contain Indonesia.');
        System.assert(countries.contains('Thailand'), 'Should contain Thailand.');
        System.assert(countries.contains('Vietnam'), 'Should contain Vietnam.');
        System.assert(countries.contains('Philippines'), 'Should contain Philippines.');
        System.assert(countries.contains('Malaysia'), 'Should contain Malaysia.');

        // Verify it returns a clone, not the original
        Integer originalSize = countries.size();
        countries.add('Antarctica');
        Set<String> freshCopy = APACDataResidencyCheck.getAPACCountries();
        System.assertEquals(originalSize, freshCopy.size(),
            'getAPACCountries should return a defensive copy.');
    }

    @IsTest
    static void testIsAPACResident_MultipleAPACCountries() {
        // Test several APAC countries via direct instantiation
        List<String> testCountries = new List<String>{
            'India', 'Singapore', 'South Korea', 'New Zealand', 'Vietnam', 'Thailand'
        };

        Test.startTest();
        for (String country : testCountries) {
            Account acc = new Account(Name = 'Test ' + country, BillingCountry = country);
            System.assertEquals(true, APACDataResidencyCheck.isAPACResident(acc),
                country + ' should be recognized as APAC.');
        }
        Test.stopTest();
    }
}
