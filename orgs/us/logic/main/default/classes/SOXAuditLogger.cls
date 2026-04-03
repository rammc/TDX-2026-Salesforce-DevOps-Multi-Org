/**
 * @description US-specific SOX compliance audit logger that tracks field-level changes
 *              on financially relevant objects. Provides both single-record and bulk
 *              change detection capabilities for audit trail requirements.
 * @group US Compliance
 * @author DevOps Multi-Org Blueprint
 */
public with sharing class SOXAuditLogger {

    private static final Set<String> SOX_RELEVANT_OBJECTS = new Set<String>{
        'Account',
        'Opportunity',
        'Contract'
    };

    private static final String LOG_PREFIX = '[SOX_AUDIT]';

    /**
     * @description Logs a single field change event for SOX audit purposes.
     *              In this demo implementation, the log entry is written via System.debug.
     *              In a production environment, this would insert a record into a
     *              custom SOX_Audit_Log__c object.
     * @param objectName The API name of the SObject being modified
     * @param recordId The Id of the record being modified
     * @param fieldName The API name of the field that changed
     * @param oldValue The previous value of the field (as a String)
     * @param newValue The new value of the field (as a String)
     */
    public static void logFieldChange(
        String objectName,
        Id recordId,
        String fieldName,
        String oldValue,
        String newValue
    ) {
        if (String.isBlank(objectName) || recordId == null || String.isBlank(fieldName)) {
            throw new SOXAuditException(
                'SOX audit log requires objectName, recordId, and fieldName.'
            );
        }

        String logEntry = String.format(
            '{0} Object={1} RecordId={2} Field={3} OldValue="{4}" NewValue="{5}" Timestamp={6} User={7}',
            new List<String>{
                LOG_PREFIX,
                objectName,
                String.valueOf(recordId),
                fieldName,
                oldValue != null ? oldValue : '',
                newValue != null ? newValue : '',
                String.valueOf(Datetime.now()),
                UserInfo.getUserId()
            }
        );

        System.debug(LoggingLevel.INFO, logEntry);
    }

    /**
     * @description Compares old and new versions of records and logs changes for
     *              all specified audited fields. Designed for use in trigger contexts
     *              where Trigger.old and Trigger.new are available.
     * @param oldRecords The list of records before modification (Trigger.old)
     * @param newRecords The list of records after modification (Trigger.new)
     * @param auditedFields The set of field API names to monitor for changes
     */
    public static void logBulkChanges(
        List<SObject> oldRecords,
        List<SObject> newRecords,
        Set<String> auditedFields
    ) {
        if (oldRecords == null || newRecords == null || auditedFields == null) {
            return;
        }

        if (oldRecords.size() != newRecords.size()) {
            throw new SOXAuditException(
                'Old and new record lists must be the same size.'
            );
        }

        String objectName = newRecords.isEmpty()
            ? 'Unknown'
            : newRecords[0].getSObjectType().getDescribe().getName();

        for (Integer i = 0; i < newRecords.size(); i++) {
            SObject oldRecord = oldRecords[i];
            SObject newRecord = newRecords[i];

            for (String fieldName : auditedFields) {
                Object oldVal = oldRecord.get(fieldName);
                Object newVal = newRecord.get(fieldName);

                if (oldVal != newVal) {
                    logFieldChange(
                        objectName,
                        newRecord.Id,
                        fieldName,
                        oldVal != null ? String.valueOf(oldVal) : null,
                        newVal != null ? String.valueOf(newVal) : null
                    );
                }
            }
        }
    }

    /**
     * @description Determines whether the given SObject API name is considered
     *              SOX-relevant for audit logging purposes. Currently covers
     *              Account, Opportunity, and Contract.
     * @param objectApiName The API name of the SObject to check
     * @return True if the object is SOX-relevant, false otherwise
     */
    public static Boolean isSOXRelevantObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return false;
        }
        return SOX_RELEVANT_OBJECTS.contains(objectApiName);
    }

    /**
     * @description Custom exception class for SOX audit logging errors.
     */
    public class SOXAuditException extends Exception {}
}
