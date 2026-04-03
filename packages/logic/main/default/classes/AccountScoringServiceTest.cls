/**
 * @description Test class for AccountScoringService. Covers high-score (Platinum),
 *              low-score (Bronze) accounts, bulk scoring, score band boundaries,
 *              and edge cases.
 * @group Logic
 */
@IsTest
private class AccountScoringServiceTest {

    @IsTest
    static void testCalculateScore_PlatinumAccount() {
        // All scoring criteria met: GlobalId(+20) + Revenue>1M(+30) + Revenue>10M(+20) + Employees>100(+15) + Technology(+15) = 100
        Account acc = new Account(
            Name = 'Platinum Corp',
            Global_Customer_ID__c = 'GBL-EU-00000001',
            AnnualRevenue = 50000000,
            NumberOfEmployees = 5000,
            Industry = 'Technology'
        );

        Integer score = AccountScoringService.calculateScore(acc);

        System.assertEquals(100, score, 'Account meeting all criteria should score 100');
        System.assertEquals('Platinum', AccountScoringService.getScoreBand(score), 'Score of 100 should be Platinum');
    }

    @IsTest
    static void testCalculateScore_GoldAccount() {
        // GlobalId(+20) + Revenue>1M(+30) + Finance(+15) = 65
        Account acc = new Account(
            Name = 'Gold Corp',
            Global_Customer_ID__c = 'GBL-US-00000002',
            AnnualRevenue = 5000000,
            NumberOfEmployees = 50,
            Industry = 'Finance'
        );

        Integer score = AccountScoringService.calculateScore(acc);

        System.assertEquals(65, score, 'Should score 65 (GlobalId + Revenue>1M + Finance)');
        System.assertEquals('Gold', AccountScoringService.getScoreBand(score), 'Score of 65 should be Gold');
    }

    @IsTest
    static void testCalculateScore_SilverAccount() {
        // Revenue>1M(+30) + Employees>100(+15) = 45
        Account acc = new Account(
            Name = 'Silver Corp',
            AnnualRevenue = 2000000,
            NumberOfEmployees = 200,
            Industry = 'Healthcare'
        );

        Integer score = AccountScoringService.calculateScore(acc);

        System.assertEquals(45, score, 'Should score 45 (Revenue>1M + Employees>100)');
        System.assertEquals('Silver', AccountScoringService.getScoreBand(score), 'Score of 45 should be Silver');
    }

    @IsTest
    static void testCalculateScore_BronzeAccount() {
        // No criteria met = 0
        Account acc = new Account(
            Name = 'Bronze Corp',
            AnnualRevenue = 500000,
            NumberOfEmployees = 10,
            Industry = 'Manufacturing'
        );

        Integer score = AccountScoringService.calculateScore(acc);

        System.assertEquals(0, score, 'Account meeting no criteria should score 0');
        System.assertEquals('Bronze', AccountScoringService.getScoreBand(score), 'Score of 0 should be Bronze');
    }

    @IsTest
    static void testCalculateScore_NullFieldsHandledGracefully() {
        // All nullable fields are null
        Account acc = new Account(
            Name = 'Minimal Corp'
        );

        Integer score = AccountScoringService.calculateScore(acc);

        System.assertEquals(0, score, 'Account with all null scoring fields should score 0');
    }

    @IsTest
    static void testCalculateScore_NullAccountThrowsException() {
        try {
            AccountScoringService.calculateScore(null);
            System.assert(false, 'Should have thrown IllegalArgumentException for null account');
        } catch (IllegalArgumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('not be null'),
                'Exception message should mention null. Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void testCalculateScore_RevenueExactlyAtThreshold() {
        // Revenue exactly at 1M boundary should NOT score (must be > 1M)
        Account acc = new Account(
            Name = 'Boundary Corp',
            AnnualRevenue = 1000000
        );

        Integer score = AccountScoringService.calculateScore(acc);

        System.assertEquals(0, score, 'Revenue exactly at 1M should not score (must be > 1M)');
    }

    @IsTest
    static void testCalculateScore_RevenueJustAbove1M() {
        // Revenue just above 1M should score +30
        Account acc = new Account(
            Name = 'Just Over Corp',
            AnnualRevenue = 1000001
        );

        Integer score = AccountScoringService.calculateScore(acc);

        System.assertEquals(30, score, 'Revenue just above 1M should score 30');
    }

    @IsTest
    static void testCalculateScore_RevenueExactlyAt10M() {
        // Revenue exactly at 10M should score +30 only (>1M), not the >10M bonus
        Account acc = new Account(
            Name = 'Ten Million Corp',
            AnnualRevenue = 10000000
        );

        Integer score = AccountScoringService.calculateScore(acc);

        System.assertEquals(30, score, 'Revenue exactly at 10M should score 30 (>1M only, not >10M)');
    }

    @IsTest
    static void testGetScoreBand_BoundaryValues() {
        System.assertEquals('Platinum', AccountScoringService.getScoreBand(80), 'Score 80 should be Platinum');
        System.assertEquals('Gold', AccountScoringService.getScoreBand(79), 'Score 79 should be Gold');
        System.assertEquals('Gold', AccountScoringService.getScoreBand(60), 'Score 60 should be Gold');
        System.assertEquals('Silver', AccountScoringService.getScoreBand(59), 'Score 59 should be Silver');
        System.assertEquals('Silver', AccountScoringService.getScoreBand(40), 'Score 40 should be Silver');
        System.assertEquals('Bronze', AccountScoringService.getScoreBand(39), 'Score 39 should be Bronze');
        System.assertEquals('Bronze', AccountScoringService.getScoreBand(0), 'Score 0 should be Bronze');
    }

    @IsTest
    static void testGetScoreBand_NullScore() {
        System.assertEquals('Bronze', AccountScoringService.getScoreBand(null), 'Null score should default to Bronze');
    }

    @IsTest
    static void testGetScoreBand_HighScore() {
        System.assertEquals('Platinum', AccountScoringService.getScoreBand(100), 'Score 100 should be Platinum');
        System.assertEquals('Platinum', AccountScoringService.getScoreBand(150), 'Score above 100 should still be Platinum');
    }

    @IsTest
    static void testBulkScore_MultipleAccounts() {
        List<Account> accounts = new List<Account>();

        Account platinumAcc = new Account(
            Name = 'Bulk Platinum',
            Global_Customer_ID__c = 'GBL-EU-00000010',
            AnnualRevenue = 50000000,
            NumberOfEmployees = 500,
            Industry = 'Technology'
        );
        insert platinumAcc;
        accounts.add(platinumAcc);

        Account bronzeAcc = new Account(
            Name = 'Bulk Bronze',
            AnnualRevenue = 100000,
            NumberOfEmployees = 5,
            Industry = 'Agriculture'
        );
        insert bronzeAcc;
        accounts.add(bronzeAcc);

        Test.startTest();
        Map<Id, Integer> scores = AccountScoringService.bulkScore(accounts);
        Test.stopTest();

        System.assertEquals(2, scores.size(), 'Should have scores for 2 accounts');
        System.assertEquals(100, scores.get(platinumAcc.Id), 'Platinum account should score 100');
        System.assertEquals(0, scores.get(bronzeAcc.Id), 'Bronze account should score 0');
    }

    @IsTest
    static void testBulkScore_EmptyList() {
        Test.startTest();
        Map<Id, Integer> scores = AccountScoringService.bulkScore(new List<Account>());
        Test.stopTest();

        System.assertEquals(0, scores.size(), 'Empty list should produce empty map');
    }

    @IsTest
    static void testBulkScore_NullListThrowsException() {
        try {
            AccountScoringService.bulkScore(null);
            System.assert(false, 'Should have thrown IllegalArgumentException for null list');
        } catch (IllegalArgumentException e) {
            System.assert(
                e.getMessage().containsIgnoreCase('not be null'),
                'Exception message should mention null'
            );
        }
    }

    @IsTest
    static void testCalculateScore_FinanceIndustry() {
        // Verify Finance industry also qualifies for +15
        Account acc = new Account(
            Name = 'Finance Corp',
            Industry = 'Finance'
        );

        Integer score = AccountScoringService.calculateScore(acc);

        System.assertEquals(15, score, 'Finance industry should add 15 points');
    }

    @IsTest
    static void testCalculateScore_NonHighValueIndustry() {
        // Verify a non-high-value industry gets no industry bonus
        Account acc = new Account(
            Name = 'Retail Corp',
            Industry = 'Retail'
        );

        Integer score = AccountScoringService.calculateScore(acc);

        System.assertEquals(0, score, 'Retail industry should not add points');
    }
}
