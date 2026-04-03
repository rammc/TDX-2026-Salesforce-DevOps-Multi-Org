/**
 * @description EU-specific GDPR compliance handler that enforces data classification
 *              rules before allowing record operations such as exports. This class
 *              ensures that restricted or confidential data cannot leave the EU org
 *              without proper compliance status.
 * @group EU Compliance
 * @author DevOps Multi-Org Blueprint
 */
public with sharing class GDPRComplianceHandler {

    private static final Set<String> BLOCKED_CLASSIFICATIONS = new Set<String>{
        'Restricted',
        'Confidential'
    };

    /**
     * @description Determines whether a given Account record is eligible for export
     *              based on its Data Classification. Records classified as Restricted
     *              or Confidential are blocked from export.
     * @param acc The Account record to evaluate
     * @return True if the record can be exported, false if it is blocked
     */
    public static Boolean canExportRecord(Account acc) {
        if (acc == null) {
            throw new GDPRComplianceException('Account record cannot be null.');
        }
        String classification = acc.modbp__Data_Classification__c;
        if (String.isBlank(classification)) {
            return true;
        }
        return !BLOCKED_CLASSIFICATIONS.contains(classification);
    }

    /**
     * @description Validates a list of Account records for bulk export eligibility.
     *              If any Account in the list fails the export check, an exception
     *              is thrown identifying the non-compliant records.
     * @param accounts The list of Account records to validate
     * @throws GDPRComplianceException if any account is not eligible for export
     */
    public static void validateBulkExport(List<Account> accounts) {
        if (accounts == null || accounts.isEmpty()) {
            return;
        }

        List<String> blockedAccountNames = new List<String>();
        for (Account acc : accounts) {
            if (!canExportRecord(acc)) {
                blockedAccountNames.add(acc.Name);
            }
        }

        if (!blockedAccountNames.isEmpty()) {
            throw new GDPRComplianceException(
                'GDPR export blocked for ' + blockedAccountNames.size() +
                ' account(s): ' + String.join(blockedAccountNames, ', ') +
                '. Records with Restricted or Confidential classification cannot be exported.'
            );
        }
    }

    /**
     * @description Returns the compliance status for a given Account based on its
     *              data classification and whether a Global Customer ID is populated.
     *              - COMPLIANT: classification is not restricted/confidential AND Global_Customer_ID__c is set
     *              - REVIEW_REQUIRED: classification is not restricted/confidential BUT Global_Customer_ID__c is missing
     *              - BLOCKED: classification is Restricted or Confidential
     * @param acc The Account record to evaluate
     * @return The compliance status string: COMPLIANT, REVIEW_REQUIRED, or BLOCKED
     */
    public static String getComplianceStatus(Account acc) {
        if (acc == null) {
            throw new GDPRComplianceException('Account record cannot be null.');
        }

        String classification = acc.modbp__Data_Classification__c;

        if (BLOCKED_CLASSIFICATIONS.contains(classification)) {
            return 'BLOCKED';
        }

        if (String.isNotBlank(acc.modbp__Global_Customer_ID__c)) {
            return 'COMPLIANT';
        }

        return 'REVIEW_REQUIRED';
    }

    /**
     * @description Custom exception class for GDPR compliance violations.
     */
    public class GDPRComplianceException extends Exception {}
}
