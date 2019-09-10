/**
 @Name: c_Log_Test.cls
 @Tests: c_Log.cls
 @Description: Tests Logging Framework. Cannot test publishing of platform event!
 @History
  VERSION     AUTHOR           DATE            DETAIL
  1.0         Matt Evans       28/8/2019       Draft
*/

@IsTest
private class c_Log_Test extends c_TestFactory {

    /**
    * Ensure custom metadata has a default value
    */
    @IsTest
    static void checkSettings() {
        // Ensure the code gives values for these constants
        System.Assert(c_log.DEBUG_PREFIX!=null,'DEBUG_PREFIX not set');
        System.Assert(c_log.DEBUG_LOGGING!=null,'DEBUG_LOGGING not set');
        System.Assert(c_log.EVENT_CATEGORIES!=null,'EVENT_CATEGORIES not set');
        System.Assert(c_log.SEND_ALL_IMPORTANT_EVENTS!=null,'SEND_ALL_IMPORTANT_EVENTS not set');
        System.Assert(c_log.MONITOR_LIMITS!=null,'MONITOR_LIMITS not set');
        System.Assert(c_log.LIMIT_WARNING_THRESHOLD!=null,'LIMIT_WARNING_THRESHOLD not set');

        // Check the options are set in for default in settings
        c_LogSetting__mdt[] matchingOptions;
        matchingOptions = [SELECT 
                Default__c,  UserName__c, Profile_ID__c,
                DebugLogging__c, DebugPrefix__c, 
                Categories__c, 
                Important__c,
                MonitorLimits__c,
                limitWarningThreshold__c
                FROM c_LogSetting__mdt WHERE Default__c = TRUE and Active__c = TRUE Order By Created__c DESC limit 1];
        System.Assert(matchingOptions!=null && !matchingOptions.isEmpty(), 'Custom metadata c_LogSetting__mdt is MISSING a default logging entry. This will conflate DML and cause errors in your org. Go to ther custom metadata in setup and create an entry for this object flagged with field "Default" checked');
    }

    /**
    * Check settings can vary for User and Profile Id
    */
    @IsTest
    static void test_userCanDefineSettings() {
        setDefaultContext();

        User admin = (User) make(Entity.ADMIN_USER, new User(alias='theAdmin'));
        run();

        // In memory only test for settings
        c_LogSetting__mdt matchingOptionUser = new c_LogSetting__mdt(DeveloperName= 'TestUser', UserName__c = admin.UserName);
        c_LogSetting__mdt matchingOptionProfile = new c_LogSetting__mdt(DeveloperName= 'TestProfile', Profile_ID__c = admin.ProfileId);
        c_LogSetting__mdt matchingOptionDefault = new c_LogSetting__mdt(DeveloperName= 'TestDefault', Default__c = TRUE);

        c_LogSetting__mdt options;
        options = c_Log.compareOptions(new List<c_LogSetting__mdt>{matchingOptionUser}, admin.UserName, admin.ProfileId);
        System.Assert(options!=null,'Logging method did not find logging options based on User Name. Logical fault in c_Log.matchOptions.');

        options = c_Log.compareOptions(new List<c_LogSetting__mdt>{matchingOptionProfile}, admin.UserName, admin.ProfileId);
        System.Assert(options!=null,'Logging method did not find logging options based on ProfileId. Logical fault in c_Log.matchOptions.');

        options = c_Log.compareOptions(new List<c_LogSetting__mdt>{matchingOptionDefault}, admin.UserName, admin.ProfileId);
        System.Assert(options!=null,'Logging method did not find logging options based on Default. Logical fault in c_Log.matchOptions.');
    }


    /**
    * Test push events & create log entries
    */
    @IsTest
    static void test_pushEvents() {
        // No matter the settings these should fire gracefully. Running this should provide debug logs etc. according to the options. No way to test platform events in memory, so we have to be happy with coverage :()
        c_Log.push('Test Message');
        c_Log.push(c_Log.category.OTHER, 'Test Important Categorised Message', true);
        c_Log.push(c_Log.category.DATABASE, 'A database error', 'my soql string', true);
        c_Log.push('Test Generic Important Message', true);
        c_Log.emit();

        c_Log.push('Test Message');
        c_log.flush();
    }
}