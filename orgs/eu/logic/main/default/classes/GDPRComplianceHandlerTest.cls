/**
 * @description Test class for GDPRComplianceHandler. Validates export eligibility,
 *              bulk export validation, and compliance status logic across all
 *              data classification scenarios.
 * @group EU Compliance
 */
@IsTest
private class GDPRComplianceHandlerTest {

    @TestSetup
    static void setupTestData() {
        List<Account> accounts = new List<Account>();

        accounts.add(new Account(
            Name = 'Public Account',
            modbp__Data_Classification__c = 'Public',
            modbp__Global_Customer_ID__c = 'GC-001'
        ));
        accounts.add(new Account(
            Name = 'Restricted Account',
            modbp__Data_Classification__c = 'Restricted',
            modbp__Global_Customer_ID__c = 'GC-002'
        ));
        accounts.add(new Account(
            Name = 'Confidential Account',
            modbp__Data_Classification__c = 'Confidential',
            modbp__Global_Customer_ID__c = 'GC-003'
        ));
        accounts.add(new Account(
            Name = 'Internal Account',
            modbp__Data_Classification__c = 'Internal',
            modbp__Global_Customer_ID__c = null
        ));
        accounts.add(new Account(
            Name = 'No Classification Account',
            modbp__Data_Classification__c = null,
            modbp__Global_Customer_ID__c = 'GC-005'
        ));

        insert accounts;
    }

    @IsTest
    static void testCanExportRecord_PublicClassification() {
        Account acc = [
            SELECT Name, modbp__Data_Classification__c, modbp__Global_Customer_ID__c
            FROM Account
            WHERE Name = 'Public Account'
            LIMIT 1
        ];

        Test.startTest();
        Boolean result = GDPRComplianceHandler.canExportRecord(acc);
        Test.stopTest();

        System.assertEquals(true, result, 'Public classification should allow export.');
    }

    @IsTest
    static void testCanExportRecord_RestrictedClassification() {
        Account acc = [
            SELECT Name, modbp__Data_Classification__c, modbp__Global_Customer_ID__c
            FROM Account
            WHERE Name = 'Restricted Account'
            LIMIT 1
        ];

        Test.startTest();
        Boolean result = GDPRComplianceHandler.canExportRecord(acc);
        Test.stopTest();

        System.assertEquals(false, result, 'Restricted classification should block export.');
    }

    @IsTest
    static void testCanExportRecord_ConfidentialClassification() {
        Account acc = [
            SELECT Name, modbp__Data_Classification__c, modbp__Global_Customer_ID__c
            FROM Account
            WHERE Name = 'Confidential Account'
            LIMIT 1
        ];

        Test.startTest();
        Boolean result = GDPRComplianceHandler.canExportRecord(acc);
        Test.stopTest();

        System.assertEquals(false, result, 'Confidential classification should block export.');
    }

    @IsTest
    static void testCanExportRecord_NullClassification() {
        Account acc = [
            SELECT Name, modbp__Data_Classification__c, modbp__Global_Customer_ID__c
            FROM Account
            WHERE Name = 'No Classification Account'
            LIMIT 1
        ];

        Test.startTest();
        Boolean result = GDPRComplianceHandler.canExportRecord(acc);
        Test.stopTest();

        System.assertEquals(true, result, 'Null classification should allow export.');
    }

    @IsTest
    static void testCanExportRecord_NullAccount() {
        Test.startTest();
        try {
            GDPRComplianceHandler.canExportRecord(null);
            System.assert(false, 'Expected GDPRComplianceException for null account.');
        } catch (GDPRComplianceHandler.GDPRComplianceException e) {
            System.assert(e.getMessage().contains('cannot be null'), 'Exception message should indicate null account.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidateBulkExport_AllAllowed() {
        List<Account> accounts = [
            SELECT Name, modbp__Data_Classification__c, modbp__Global_Customer_ID__c
            FROM Account
            WHERE modbp__Data_Classification__c IN ('Public', 'Internal')
               OR modbp__Data_Classification__c = null
        ];

        Test.startTest();
        try {
            GDPRComplianceHandler.validateBulkExport(accounts);
            // Should not throw
            System.assert(true, 'Bulk export should succeed for non-restricted accounts.');
        } catch (GDPRComplianceHandler.GDPRComplianceException e) {
            System.assert(false, 'Should not throw exception for exportable accounts.');
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidateBulkExport_MixedList() {
        List<Account> accounts = [
            SELECT Name, modbp__Data_Classification__c, modbp__Global_Customer_ID__c
            FROM Account
        ];

        Test.startTest();
        try {
            GDPRComplianceHandler.validateBulkExport(accounts);
            System.assert(false, 'Expected GDPRComplianceException for mixed list.');
        } catch (GDPRComplianceHandler.GDPRComplianceException e) {
            System.assert(
                e.getMessage().contains('GDPR export blocked'),
                'Exception message should indicate GDPR export block.'
            );
            System.assert(
                e.getMessage().contains('Restricted Account') || e.getMessage().contains('Confidential Account'),
                'Exception message should reference blocked account names.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testValidateBulkExport_EmptyList() {
        Test.startTest();
        GDPRComplianceHandler.validateBulkExport(new List<Account>());
        GDPRComplianceHandler.validateBulkExport(null);
        Test.stopTest();
        // No exception expected — passes silently
        System.assert(true, 'Empty or null list should not throw.');
    }

    @IsTest
    static void testGetComplianceStatus_Compliant() {
        Account acc = [
            SELECT Name, modbp__Data_Classification__c, modbp__Global_Customer_ID__c
            FROM Account
            WHERE Name = 'Public Account'
            LIMIT 1
        ];

        Test.startTest();
        String status = GDPRComplianceHandler.getComplianceStatus(acc);
        Test.stopTest();

        System.assertEquals('COMPLIANT', status,
            'Public classification with Global Customer ID should be COMPLIANT.');
    }

    @IsTest
    static void testGetComplianceStatus_ReviewRequired() {
        Account acc = [
            SELECT Name, modbp__Data_Classification__c, modbp__Global_Customer_ID__c
            FROM Account
            WHERE Name = 'Internal Account'
            LIMIT 1
        ];

        Test.startTest();
        String status = GDPRComplianceHandler.getComplianceStatus(acc);
        Test.stopTest();

        System.assertEquals('REVIEW_REQUIRED', status,
            'Non-restricted classification without Global Customer ID should be REVIEW_REQUIRED.');
    }

    @IsTest
    static void testGetComplianceStatus_Blocked() {
        Account acc = [
            SELECT Name, modbp__Data_Classification__c, modbp__Global_Customer_ID__c
            FROM Account
            WHERE Name = 'Restricted Account'
            LIMIT 1
        ];

        Test.startTest();
        String status = GDPRComplianceHandler.getComplianceStatus(acc);
        Test.stopTest();

        System.assertEquals('BLOCKED', status,
            'Restricted classification should be BLOCKED regardless of Global Customer ID.');
    }

    @IsTest
    static void testGetComplianceStatus_BlockedConfidential() {
        Account acc = [
            SELECT Name, modbp__Data_Classification__c, modbp__Global_Customer_ID__c
            FROM Account
            WHERE Name = 'Confidential Account'
            LIMIT 1
        ];

        Test.startTest();
        String status = GDPRComplianceHandler.getComplianceStatus(acc);
        Test.stopTest();

        System.assertEquals('BLOCKED', status,
            'Confidential classification should be BLOCKED.');
    }

    @IsTest
    static void testGetComplianceStatus_NullAccount() {
        Test.startTest();
        try {
            GDPRComplianceHandler.getComplianceStatus(null);
            System.assert(false, 'Expected GDPRComplianceException for null account.');
        } catch (GDPRComplianceHandler.GDPRComplianceException e) {
            System.assert(e.getMessage().contains('cannot be null'), 'Exception message should indicate null account.');
        }
        Test.stopTest();
    }
}
