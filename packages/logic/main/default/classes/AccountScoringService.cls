/**
 * @description Service class for scoring Account records based on key business
 *              attributes. Produces a numeric score and classifies accounts into
 *              tier bands (Platinum, Gold, Silver, Bronze).
 * @group Logic
 */
public with sharing class AccountScoringService {

    private static final Integer POINTS_HAS_GLOBAL_ID     = 20;
    private static final Integer POINTS_REVENUE_OVER_1M   = 30;
    private static final Integer POINTS_REVENUE_OVER_10M  = 20;
    private static final Integer POINTS_EMPLOYEES_OVER_100 = 15;
    private static final Integer POINTS_HIGH_VALUE_INDUSTRY = 15;

    private static final Integer THRESHOLD_PLATINUM = 80;
    private static final Integer THRESHOLD_GOLD     = 60;
    private static final Integer THRESHOLD_SILVER   = 40;

    private static final Set<String> HIGH_VALUE_INDUSTRIES = new Set<String>{
        'Technology', 'Finance'
    };

    /**
     * @description Calculates a score for the given Account based on business attributes.
     *              Scoring criteria:
     *              - Has Global_Customer_ID__c: +20
     *              - AnnualRevenue > 1,000,000: +30
     *              - AnnualRevenue > 10,000,000: +20 (additional)
     *              - NumberOfEmployees > 100: +15
     *              - Industry is Technology or Finance: +15
     * @param acc The Account record to score (must not be null)
     * @return The calculated score (0-100)
     * @throws IllegalArgumentException if acc is null
     */
    public static Integer calculateScore(Account acc) {
        if (acc == null) {
            throw new IllegalArgumentException('Account must not be null.');
        }

        Integer score = 0;

        // Global Customer ID presence
        if (String.isNotBlank(acc.Global_Customer_ID__c)) {
            score += POINTS_HAS_GLOBAL_ID;
        }

        // Annual Revenue tiers
        if (acc.AnnualRevenue != null && acc.AnnualRevenue > 1000000) {
            score += POINTS_REVENUE_OVER_1M;
            if (acc.AnnualRevenue > 10000000) {
                score += POINTS_REVENUE_OVER_10M;
            }
        }

        // Employee count
        if (acc.NumberOfEmployees != null && acc.NumberOfEmployees > 100) {
            score += POINTS_EMPLOYEES_OVER_100;
        }

        // High-value industry
        if (String.isNotBlank(acc.Industry) && HIGH_VALUE_INDUSTRIES.contains(acc.Industry)) {
            score += POINTS_HIGH_VALUE_INDUSTRY;
        }

        return score;
    }

    /**
     * @description Returns the score band label for a given numeric score.
     * @param score The numeric score to classify
     * @return 'Platinum' (>=80), 'Gold' (>=60), 'Silver' (>=40), or 'Bronze' (<40)
     */
    public static String getScoreBand(Integer score) {
        if (score == null) {
            return 'Bronze';
        }

        if (score >= THRESHOLD_PLATINUM) {
            return 'Platinum';
        } else if (score >= THRESHOLD_GOLD) {
            return 'Gold';
        } else if (score >= THRESHOLD_SILVER) {
            return 'Silver';
        } else {
            return 'Bronze';
        }
    }

    /**
     * @description Calculates scores for a list of Account records in bulk.
     * @param accounts The list of Account records to score
     * @return A map of Account Id to calculated score
     * @throws IllegalArgumentException if accounts is null
     */
    public static Map<Id, Integer> bulkScore(List<Account> accounts) {
        if (accounts == null) {
            throw new IllegalArgumentException('Accounts list must not be null.');
        }

        Map<Id, Integer> scoreMap = new Map<Id, Integer>();

        for (Account acc : accounts) {
            if (acc.Id != null) {
                scoreMap.put(acc.Id, calculateScore(acc));
            }
        }

        return scoreMap;
    }
}
