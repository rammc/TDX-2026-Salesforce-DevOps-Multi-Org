/**
 * @description Routes outbound API calls based on Integration_Setting__mdt custom metadata
 *              records. Provides a centralized mechanism for looking up integration
 *              configuration and executing HTTP callouts with the correct endpoint and timeout.
 * @group Integration
 */
public with sharing class IntegrationRouter {

    /**
     * @description Routes an HTTP request to the endpoint defined in the specified
     *              Integration_Setting__mdt record. The setting must be active.
     * @param settingName The DeveloperName of the Integration_Setting__mdt record
     * @param method The HTTP method (GET, POST, PUT, PATCH, DELETE)
     * @param body The request body (can be null for GET/DELETE)
     * @return The HttpResponse from the callout
     * @throws IntegrationException if the setting is not found or not active
     */
    public static HttpResponse route(String settingName, String method, String body) {
        Integration_Setting__mdt setting = getActiveSetting(settingName);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(setting.Endpoint__c);
        req.setMethod(method.toUpperCase());
        req.setTimeout(Integer.valueOf(setting.Timeout_Ms__c));
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');

        if (String.isNotBlank(body) && method.toUpperCase() != 'GET' && method.toUpperCase() != 'DELETE') {
            req.setBody(body);
        }

        Http http = new Http();
        return http.send(req);
    }

    /**
     * @description Retrieves an active Integration_Setting__mdt record by DeveloperName.
     * @param developerName The DeveloperName of the Integration_Setting__mdt record
     * @return The active Integration_Setting__mdt record
     * @throws IntegrationException if the setting is not found or not active
     */
    public static Integration_Setting__mdt getActiveSetting(String developerName) {
        if (String.isBlank(developerName)) {
            throw new IntegrationException('Setting developer name must not be null or blank.');
        }

        List<Integration_Setting__mdt> settings = [
            SELECT DeveloperName, Endpoint__c, Timeout_Ms__c, Is_Active__c, Region__c
            FROM Integration_Setting__mdt
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];

        if (settings.isEmpty()) {
            throw new IntegrationException(
                'Integration setting not found: ' + developerName
            );
        }

        Integration_Setting__mdt setting = settings[0];

        if (!setting.Is_Active__c) {
            throw new IntegrationException(
                'Integration setting is not active: ' + developerName
            );
        }

        return setting;
    }

    /**
     * @description Checks whether an integration setting exists and is active.
     * @param settingName The DeveloperName of the Integration_Setting__mdt record
     * @return true if the setting exists and Is_Active__c is true, false otherwise
     */
    public static Boolean isServiceAvailable(String settingName) {
        if (String.isBlank(settingName)) {
            return false;
        }

        List<Integration_Setting__mdt> settings = [
            SELECT Is_Active__c
            FROM Integration_Setting__mdt
            WHERE DeveloperName = :settingName
            LIMIT 1
        ];

        return !settings.isEmpty() && settings[0].Is_Active__c;
    }

    /**
     * @description Custom exception for integration routing errors.
     */
    public class IntegrationException extends Exception {}
}
