/**
 @Name: c_Log.cls
 @TestedBy: c_Log_Test.cls
 @Description: 
  Logging framework writes out debug logs, monitors limits and publishes log entries as Platform Eventds and debug statements. 
  Purpose: To allow critical events to be logged as an Event, especially when key processes fail or limits are being reached.
  Options are driven by Custom MetaData c_LogSetting__mtd. 
  Custom settings define how we log with a default setting or by username / profileid
  - Generate platform events when a log entry of speciffic cateogory is added, or when important (default false)
  - Create Debug statements (default false) with a defined Debug prefix (default @@)
  - Choose which limit to monitor and set a Limit warning threshold (default 75%)

 @Usage 
    c_log.send([logCategory], logMessage, [important])); // Send a single log event
    c_log.push([logCategory], logMessage, [important])); // Push a log entry to the stack
    c_log.emit(); // To have the current set of logs published.ApexPages
    c_log.flush(); // Returns log as JSON and clears the current log (called by emit() automatically)
    To react to events, (ex. email an admin or store the event), have a Process Builder workflow subscribed to the event, that will email / react to the issue.
 
 @TODO: 
    Slim down the CPU time on limit cheking, maybe dont use another object. 
    Prevent user from deactivating or unchecking Default on a Setting marked as default when there is no other active default record

 @History
  VERSION     AUTHOR           DATE            DETAIL
  1.0         Matt Evans       28/8/2019       Draft
  1.1         Matt Evans       28/8/2019       CPU Review
*/

public without sharing class c_Log {
    // Log Entries
    static List<LogEventData> log = new List<LogEventData>();
    
    // Log constants for options
    public ENUM monitorLimit {BASICS,APEX,CALLOUTS,DATABASE}
    public ENUM category {EVENT, ERROR, INTEGRATION, DATABASE, PROCESS, ALERT, OTHER}
    public ENUM platformLimit {QueueableJobs,HeapSize,CpuTime,Callouts,AsyncCalls,SoslQueries,DMLStatements,DMLRows,Queries,QueryRows,AggregateQueries}

    // Logging options from custom metadata
    public static final String DEBUG_PREFIX = getDebugPrefix();
    public static final Boolean DEBUG_LOGGING = getDebugLogging();
    public static final Boolean EVENTLOGGING = getEventLogging();
    public static final Set<category> EVENT_CATEGORIES = getListOfCategoriesForPlatformEvents(); // Should include an ALL or * wildcard in the setting field to include the whole ENUM list
    public static final Boolean SEND_ALL_IMPORTANT_EVENTS = getFlagToSendAllImportantEntriesAsEvents();
    public static final Set<c_Log.monitorLimit> MONITOR_LIMITS = getMonitorLimits();
    public static final Integer LIMIT_WARNING_THRESHOLD = getLimitWarningThreshold();

    // Platform Event Summary data (used for the c_Log__e event fields)
    static String PE_title = '';
    static Set<String> PE_categories = new Set<String>();
    static Boolean PE_Important = FALSE;
    static Boolean PE_LimitWarning = FALSE;


    /**
    * SEND the log event immediately (immediate logging)
    */
    public static void send(String logMessage)
    {
        push(category.EVENT, logMessage, '', false);
        emit();
    }
    public static void send(String logMessage, Boolean important)
    {
        push(category.EVENT, logMessage, '', important);
        emit();
    }
    public static void send(category logCategory, String logMessage, Boolean important)
    {    
        push(logCategory, logMessage, '', important);
        emit();
    }

    /**
    * PUSH logs to the stack (when multiple logs want to be collected)
    */

    // Generic log push; Logging options driven by custom settings
    // If multiple logs are to be recorded, then use 'push' then 'emit'
    public static void push(String logMessage)
    {
        push(category.EVENT, logMessage, '', false);
    }
    public static void push(String logMessage, Boolean important)
    {
        push(category.EVENT, logMessage, '', important);
    }
    public static void push(category logCategory, String logMessage, Boolean important)
    {    
        push(logCategory, logMessage, '', important);
    }

    /**
    * Main push method
    */ 
    public static void push(category logCategory, String msg, String soql, Boolean important) {
        
        LogEventData logData = new LogEventData(logCategory, msg, soql, important);

        // Create platform event for important events or those in categories we are monitoring 
        // - Not all log events are sent via the bus, it depends on the custom metadata settings in c_LogSetting__mdt
        if (SEND_ALL_IMPORTANT_EVENTS && important || EVENT_CATEGORIES.contains(logCategory)) {
            log.add(logData);

            // build the title and properties that we will use in the platform event along with the serialised log data
            PE_categories.add(''+logCategory);
            PE_Important = logData.important ? true : PE_Important;
            PE_LimitWarning = logData.limitWarning ? true : PE_LimitWarning;
        }
        
        // Write to debug log if required
        if (DEBUG_LOGGING) {
            String strDebug;
            System.debug(important ? LoggingLevel.ERROR :  LoggingLevel.INFO, DEBUG_PREFIX + ' ' + (logCategory != null ? logCategory : c_Log.category.OTHER) + ' '+(important ? '/!\\ IMPORTANT /!\\' : '')+' @'+logData.timestamp+' ' + (msg!= null && msg!='' ? ' Msg: ' + msg  : ''));
            if (soql!=null && soql!='') {
                System.debug(important ? LoggingLevel.ERROR :  LoggingLevel.INFO, DEBUG_PREFIX + ' Soql: ' + soql);
            }
            if (logData.limitReport!=null && logData.limitReport!='') {
                System.debug(important ? LoggingLevel.ERROR :  LoggingLevel.INFO, DEBUG_PREFIX + ' Limits: ' + logData.limitReport);
            }
        }
    }

    /**
    * Emits the current log state to the Log__e platform event
    **/
    public static void emit()
    {   
        // Emit the log data via Platform Events and clear
        if (!log.isEmpty() && EVENTLOGGING) {
            EventBus.publish(
            new c_Log__e(
                Title__c = (PE_Important ? 'IMPORTANT ' : '') +String.join((Iterable<String>)PE_categories,','),
                Categories__c = String.join((Iterable<String>)PE_categories,','),
                Important__c = PE_Important,
                LimitWarning__c = PE_LimitWarning,
                Data__c = flush()));
        }
    }

    /**
	 * Flush the log entries to JSON and clear log
	 **/   
    public static String flush()
    {
        String logData = System.JSON.serialize(log, true);
        log = new List<LogEventData>();
        PE_categories = new Set<String>();
        PE_Important = false;
        PE_LimitWarning = false;
        PE_title = '';
		return logData;  
    }

    /**
    * Log Container
    */
    public class LogEventData {
        public final Datetime timestamp;
        public final c_Log.category logCategory; 
        public final String msg;
        public final String soql;
        public final Boolean important;

        public Boolean limitWarning;
        public string limitReport;

        public LogEventData(c_Log.category logCategory, String msg, String soql, Boolean important) {
            this.timestamp = System.now();
            this.msg = msg;
            this.soql = soql;
            this.limitWarning = FALSE;
            this.important = important;
            this.limitReport = getLimitReport();
        }

        string getLimitReport() {
            String strLimits = '';
            
            // System.debug('@@ c_Log.MONITOR_LIMITS '+c_Log.MONITOR_LIMITS+' c_Log.MONITOR_LIMITS.isEmpty() '+c_Log.MONITOR_LIMITS.isEmpty());
            if (!c_Log.MONITOR_LIMITS.isEmpty())
            {
                if (c_Log.MONITOR_LIMITS.contains(c_Log.monitorLimit.BASICS)) {
                    // Apex
                    strLimits += checkLimit(c_Log.platformLimit.CpuTime);
                    // DML
                    strLimits += checkLimit(c_Log.platformLimit.DMLStatements);
                } else {
                    if (c_Log.MONITOR_LIMITS.contains(c_Log.monitorLimit.APEX)) {
                        // Apex
                        strLimits += checkLimit(c_Log.platformLimit.QueueableJobs);
                        strLimits += checkLimit(c_Log.platformLimit.HeapSize);
                        strLimits += checkLimit(c_Log.platformLimit.CpuTime);
                    }
                    if (c_Log.MONITOR_LIMITS.contains(c_Log.monitorLimit.CALLOUTS)) {
                        // Callouts
                        strLimits += checkLimit(c_Log.platformLimit.Callouts);
                        strLimits += checkLimit(c_Log.platformLimit.AsyncCalls);
                    }
                    if (c_Log.MONITOR_LIMITS.contains(c_Log.monitorLimit.DATABASE)) {
                        // DML
                        strLimits += checkLimit(c_Log.platformLimit.SoslQueries);
                        strLimits += checkLimit(c_Log.platformLimit.DMLStatements);
                        strLimits += checkLimit(c_Log.platformLimit.DMLRows);
                        strLimits += checkLimit(c_Log.platformLimit.Queries);
                        strLimits += checkLimit(c_Log.platformLimit.QueryRows);
                        strLimits += checkLimit(c_Log.platformLimit.AggregateQueries);
                    }
                }
            }
            return strLimits;
        }

        string checkLimit(c_Log.platformLimit platformLimitToReport) {
            c_Log.LimitStatus s = new LimitStatus(platformLimitToReport);
            this.limitWarning = s.thresholdExceeded ? true : this.limitWarning;
            return s.message;
        }
    }

    /**
    * LIMIT REPORTING CLASS 
    */
    public class LimitStatus {
        // Definition of limit comparison
        public c_Log.platformLimit limitName;
        public Integer limitThreshold = c_log.LIMIT_WARNING_THRESHOLD;

        // Metrics
        public Integer current {get{if (current==null) checkCurrent(); return current;} set{current = value;}}
        public Integer max {get{if (includeMax && max==null) checkMax(); return max;} set{max = value;}}
        Boolean includeMax {get{return limitThreshold!=null && limitThreshold>0;}set{}}

        // Assessment
        public String message {get{
            return (thresholdExceeded ? (limitPercent > limitThreshold ? '/!\\ WARNING /!\\ '+limitPercent+'% ' : '') : '') + limitName + ' : ' + current + (includeMax!=null ? ' of ' + max : '') + ', ';
        } set{}}
        public Integer limitPercent {get{return includeMax && max!=null && max!=0 ? (current/max*100) : 0;} set{}}
        public Boolean thresholdExceeded {get{return limitThreshold!=null && limitPercent>limitThreshold;} set{}}

        // Constructor
        public LimitStatus(c_Log.platformLimit limitName) {
            this.limitName = limitName;
        }

        // Fetch and set System Limits
        void checkCurrent() {
            // Should not be called repeatedly so as to avoid underperformant logging
            if (limitName == c_Log.platformLimit.QueueableJobs) {
                current = Limits.getQueueableJobs();
            } else
            if (limitName == c_Log.platformLimit.HeapSize) {
                current = Limits.getHeapSize();
            } else
            if (limitName == c_Log.platformLimit.CpuTime) {
                current = Limits.getCpuTime();
            } else
            if (limitName == c_Log.platformLimit.Callouts) {
                current = Limits.getCallouts();
            } else
            if (limitName == c_Log.platformLimit.AsyncCalls) {
                current = Limits.getAsyncCalls();
            } else
            if (limitName == c_Log.platformLimit.SoslQueries) {
                current = Limits.getSoslQueries();
            } else
            if (limitName == c_Log.platformLimit.DMLStatements) {
                current = Limits.getDMLStatements();
            } else
            if (limitName == c_Log.platformLimit.DMLRows) {
                current = Limits.getDMLRows();
            } else
            if (limitName == c_Log.platformLimit.Queries) {
                current = Limits.getQueries();
            } else
            if (limitName == c_Log.platformLimit.QueryRows) {
                current = Limits.getQueryRows();
            } else
            if (limitName == c_Log.platformLimit.AggregateQueries) {
                current = Limits.getAggregateQueries();
            }
        }

        void checkMax() {
            // Should not be called repeatedly so as to avoid underperformant logging
            if (limitName == c_Log.platformLimit.QueueableJobs) {
                max = Limits.getLimitQueueableJobs();
            } else
            if (limitName == c_Log.platformLimit.HeapSize) {
                max = Limits.getLimitHeapSize();
            } else
            if (limitName == c_Log.platformLimit.CpuTime) {
                max = Limits.getLimitCpuTime();
            } else
            if (limitName == c_Log.platformLimit.Callouts) {
                max = Limits.getLimitCallouts();
            } else
            if (limitName == c_Log.platformLimit.AsyncCalls) {
                max = Limits.getLimitAsyncCalls();
            } else
            if (limitName == c_Log.platformLimit.SoslQueries) {
                max = Limits.getLimitSoslQueries();
            } else
            if (limitName == c_Log.platformLimit.DMLStatements) {
                max = Limits.getLimitDMLStatements();
            } else
            if (limitName == c_Log.platformLimit.DMLRows) {
                max = Limits.getLimitDMLRows();
            } else
            if (limitName == c_Log.platformLimit.Queries) {
                max = Limits.getLimitQueries();
            } else
            if (limitName == c_Log.platformLimit.QueryRows) {
                max = Limits.getLimitQueryRows();
            } else
            if (limitName == c_Log.platformLimit.AggregateQueries) {
                max = Limits.getLimitAggregateQueries();
            }
        }
    }


    /**
    *   Get options from custom metadata settings in c_LogSetting__mdt
    */
    static boolean optionsQueried = false;
    static c_LogSetting__mdt options;
    static void findOptions() {
        if (optionsQueried==null || !optionsQueried) {
            optionsQueried = true;

            String username = UserInfo.getUserName();
            Id profileId = UserInfo.getProfileId();
            
            c_LogSetting__mdt[] matchingOptions = new List<c_LogSetting__mdt>();

            c_LogSetting__mdt[] matchingOptionProfile = [SELECT 
                Default__c,  UserName__c, Profile_ID__c,
                DebugLogging__c, DebugPrefix__c, 
                EventLogging__c, Categories__c, Important__c,
                limitWarningThreshold__c, MonitorLimits__c
                FROM c_LogSetting__mdt 
                WHERE 
                Active__c = TRUE AND
                Profile_ID__c = :profileId
                Order By Created__c DESC];
            
            c_LogSetting__mdt[] matchingOptionUser = [SELECT 
                Default__c,  UserName__c, Profile_ID__c,
                DebugLogging__c, DebugPrefix__c, 
                EventLogging__c, Categories__c, Important__c,
                limitWarningThreshold__c, MonitorLimits__c
                FROM c_LogSetting__mdt 
                WHERE UserName__c = :username
                AND Active__c = TRUE  
                Order By Created__c DESC];
            matchingOptions.addAll(matchingOptionUser);

            c_LogSetting__mdt[] matchingOptionDefault = [SELECT 
                Default__c,  UserName__c, Profile_ID__c,
                DebugLogging__c, DebugPrefix__c, 
                EventLogging__c, Categories__c, Important__c,
                limitWarningThreshold__c, MonitorLimits__c
                FROM c_LogSetting__mdt 
                WHERE Default__c = TRUE
                AND Active__c = TRUE  
                Order By Created__c DESC];

            matchingOptions.addAll(matchingOptionProfile);
            matchingOptions.addAll(matchingOptionUser);
            matchingOptions.addAll(matchingOptionDefault);
            
            compareOptions(matchingOptions,username,profileId);
            // System.debug('@@ options '+options);
        }
    }
    public static c_LogSetting__mdt compareOptions(c_LogSetting__mdt[] matchingOptions, String username, Id profileId) {
        // Match options on user, profile and default. Set the value so this dml will not run again.
        for (c_LogSetting__mdt ls : matchingOptions) {
            if (ls.UserName__c!=null && ls.UserName__c == username) {
                options = ls;
                return options;
            } else if (ls.Profile_ID__c!=null && ls.Profile_ID__c == profileId) {
                options = ls;
                return options;
            } else if (ls.Default__c!=null && ls.Default__c) {
                options = ls;
                return options;
            }
        }
        return options;
    }

    public static String getDebugPrefix() {
        findOptions();
        if (options!=null && options.DebugPrefix__c!=null) return options.DebugPrefix__c;
        return '@@';
    }
    public static Boolean getDebugLogging() {
        findOptions();
        if (options!=null && options.DebugPrefix__c!=null) return options.DebugLogging__c;
        return TRUE;
    }
    public static Boolean getEventLogging() {
        findOptions();
        if (options!=null) return options.EventLogging__c;
        return TRUE;
    }
    public static Set<c_Log.category> getListOfCategoriesForPlatformEvents() {
        findOptions();
        if (options!=null && options.Categories__c!=null) 
        {
            Set<c_Log.category> categorySet = new Set<c_Log.category>();

            String unparsedOptions = options.Categories__c;
            unparsedOptions += ' ';
            unparsedOptions = unparsedOptions.replace(',',' ');
            unparsedOptions = unparsedOptions.replace('  ','');
            unparsedOptions = unparsedOptions.toUpperCase();

            for (c_Log.category enumValue : c_Log.category.values())
            {
                if (unparsedOptions.contains(String.valueOf(enumValue)))
                {
                    categorySet.add(enumValue);
                }
            }

            return categorySet;
        } else if (options!=null && options.Categories__c==null) {
            return new Set<c_Log.category>();
        }
        return new Set<c_Log.category>{c_Log.category.EVENT, c_Log.category.INTEGRATION, c_Log.category.DATABASE, c_Log.category.ALERT, c_Log.category.ERROR, c_Log.category.PROCESS, c_Log.category.OTHER};
    }
    public static Boolean getFlagToSendAllImportantEntriesAsEvents() {
        findOptions();
        if (options!=null && options.Important__c!=null) return options.Important__c;
        return TRUE;
    }
    public static Set<c_Log.monitorLimit> getMonitorLimits() {
        findOptions();
        if (options!=null && options.MonitorLimits__c!=null) 
        {
            Set<c_Log.monitorLimit> monitorSet = new Set<c_Log.monitorLimit>();
            String unparsedOptions = options.MonitorLimits__c;
            unparsedOptions += ' ';
            unparsedOptions = unparsedOptions.replace(',',' ');
            unparsedOptions = unparsedOptions.replace('  ','');
            unparsedOptions = unparsedOptions.toUpperCase();

            for (c_Log.monitorLimit enumValue : c_Log.monitorLimit.values())
            {
                if (unparsedOptions.contains(String.valueOf(enumValue)))
                {
                    monitorSet.add(enumValue);
                }
            }
            return monitorSet;
        } else if (options!=null && options.MonitorLimits__c==null) {
            return new Set<c_Log.monitorLimit>();
        }
        return new Set<c_Log.monitorLimit>{c_Log.monitorLimit.BASICS};
    }
    public static Integer getLimitWarningThreshold() {
        findOptions();
        if (options!=null && options.limitWarningThreshold__c!=null) return (Integer)Math.Round(options.limitWarningThreshold__c * 100);
        return 80;
    }
}