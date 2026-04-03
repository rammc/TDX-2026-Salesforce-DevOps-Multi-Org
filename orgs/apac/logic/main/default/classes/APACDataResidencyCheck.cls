/**
 * @description APAC-specific data residency validation class that ensures Account
 *              records with restricted data classifications are stored in compliance
 *              with APAC data sovereignty requirements. Validates that restricted
 *              records belong to accounts with APAC billing addresses.
 * @group APAC Compliance
 * @author DevOps Multi-Org Blueprint
 */
public with sharing class APACDataResidencyCheck {

    private static final Set<String> APAC_COUNTRIES = new Set<String>{
        'Australia',
        'Bangladesh',
        'Brunei',
        'Cambodia',
        'China',
        'Fiji',
        'Hong Kong',
        'India',
        'Indonesia',
        'Japan',
        'Laos',
        'Macau',
        'Malaysia',
        'Maldives',
        'Mongolia',
        'Myanmar',
        'Nepal',
        'New Zealand',
        'Pakistan',
        'Papua New Guinea',
        'Philippines',
        'Singapore',
        'South Korea',
        'Sri Lanka',
        'Taiwan',
        'Thailand',
        'Timor-Leste',
        'Vietnam'
    };

    /**
     * @description Determines whether the given Account is considered an APAC resident
     *              based on its BillingCountry. An account is an APAC resident if its
     *              BillingCountry matches one of the recognized APAC countries.
     * @param acc The Account record to evaluate
     * @return True if the account's BillingCountry is in the APAC country list
     */
    public static Boolean isAPACResident(Account acc) {
        if (acc == null) {
            throw new APACDataResidencyException('Account record cannot be null.');
        }
        if (String.isBlank(acc.BillingCountry)) {
            return false;
        }
        return APAC_COUNTRIES.contains(acc.BillingCountry);
    }

    /**
     * @description Enforces data residency rules for a list of Account records.
     *              Any Account with a Data_Classification__c of 'Restricted' must have
     *              a BillingCountry within the APAC region. An exception is thrown if
     *              any restricted account violates this requirement.
     * @param accounts The list of Account records to validate
     * @throws APACDataResidencyException if any restricted account has a non-APAC BillingCountry
     */
    public static void enforceResidency(List<Account> accounts) {
        if (accounts == null || accounts.isEmpty()) {
            return;
        }

        List<String> violatingAccounts = new List<String>();

        for (Account acc : accounts) {
            String classification = acc.modbp__Data_Classification__c;
            if (classification == 'Restricted' && !isAPACResident(acc)) {
                String country = String.isNotBlank(acc.BillingCountry)
                    ? acc.BillingCountry
                    : 'unspecified';
                violatingAccounts.add(acc.Name + ' (BillingCountry: ' + country + ')');
            }
        }

        if (!violatingAccounts.isEmpty()) {
            throw new APACDataResidencyException(
                'Data residency violation: ' + violatingAccounts.size() +
                ' restricted account(s) have non-APAC billing addresses: ' +
                String.join(violatingAccounts, ', ') +
                '. Restricted records must reside within the APAC region.'
            );
        }
    }

    /**
     * @description Returns the complete set of country names recognized as part of
     *              the APAC region for data residency purposes.
     * @return An unmodifiable set of APAC country names
     */
    public static Set<String> getAPACCountries() {
        return APAC_COUNTRIES.clone();
    }

    /**
     * @description Custom exception class for APAC data residency violations.
     */
    public class APACDataResidencyException extends Exception {}
}
