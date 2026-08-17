/*
ASSIGNMENT SECTION:
Section 2 - Integrity

REQUIREMENT:
6. All valid and invalid data manipulations must be logged.

RUN AS:
sb_auditor_noor after running the preceding integrity demonstrations. Allow at
least two seconds for asynchronous SQL Server Audit delivery.

EXPECTED RESULT:
DML audit rows show committed changes and before/after evidence; application events
show successful and failed controlled operations; native audit shows denied actions.

PASS CONDITION:
The recent evidence contains successful DML, successful application operations,
failed application operations and failed native-audit events.

DATABASE CHANGES:
None. This script reads audit evidence and deliberately omits native statement text
so credentials or transaction PIN parameters cannot be shown in screenshots.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
GO

IF IS_ROLEMEMBER(N'rl_security_auditor') <> 1
    THROW 51250, 'Run this script as sb_auditor_noor.', 1;

DECLARE @StartTime datetime2(3) = DATEADD(HOUR, -2, SYSUTCDATETIME());
WAITFOR DELAY '00:00:02';

SELECT EventCategory, Mechanism, AuditAction, EvidenceLocation, CapturedEvidence
FROM audit.vw_AuditMatrix
ORDER BY EventCategory;

SELECT TOP (100) AuditID, EventTime, ActionType, SchemaName, TableName,
       AffectedRowCount, ActorLogin, DatabaseUser, CorrelationID,
       OldValues, NewValues
FROM audit.vw_DmlAudit
WHERE EventTime >= @StartTime
ORDER BY EventTime DESC, AuditID DESC;

SELECT TOP (100) EventID, EventTime, EventType, OperationName, Succeeded,
       ActorLogin, TargetType, TargetID, CorrelationID, ErrorNumber, SafeDetails
FROM audit.ApplicationEvent
WHERE EventTime >= @StartTime
ORDER BY EventTime DESC, EventID DESC;

CREATE TABLE #NativeAudit
(
    EventTimeUtc datetime2(7), ActionID varchar(4), Succeeded bit, SessionID int,
    ServerPrincipal sysname NULL, DatabasePrincipal sysname NULL, DatabaseName sysname NULL,
    SchemaName sysname NULL, ObjectName sysname NULL, StatementText nvarchar(max) NULL,
    ApplicationName nvarchar(256) NULL, ClientAddress varchar(128) NULL,
    AdditionalInformation nvarchar(max) NULL, AuditFile nvarchar(4000) NULL
);
INSERT #NativeAudit
EXEC audit.usp_ReadNativeAudit @StartTime = @StartTime, @EndTime = NULL, @OnlyFailures = 0;

SELECT TOP (100) EventTimeUtc, ActionID, Succeeded, ServerPrincipal,
       DatabasePrincipal, DatabaseName, SchemaName, ObjectName,
       ApplicationName, ClientAddress
FROM #NativeAudit
ORDER BY EventTimeUtc DESC;

DECLARE @DmlSuccesses bigint =
    (SELECT COUNT_BIG(*) FROM audit.vw_DmlAudit WHERE EventTime >= @StartTime);
DECLARE @ApplicationSuccesses bigint =
    (SELECT COUNT_BIG(*) FROM audit.ApplicationEvent WHERE EventTime >= @StartTime AND Succeeded = 1);
DECLARE @ApplicationFailures bigint =
    (SELECT COUNT_BIG(*) FROM audit.ApplicationEvent WHERE EventTime >= @StartTime AND Succeeded = 0);
DECLARE @NativeFailures bigint =
    (SELECT COUNT_BIG(*) FROM #NativeAudit WHERE Succeeded = 0);

SELECT @DmlSuccesses AS SuccessfulDmlAuditRows,
       @ApplicationSuccesses AS SuccessfulApplicationEvents,
       @ApplicationFailures AS FailedApplicationEvents,
       @NativeFailures AS FailedNativeAuditEvents,
       IIF(@DmlSuccesses > 0 AND @ApplicationSuccesses > 0
           AND @ApplicationFailures > 0 AND @NativeFailures > 0, N'PASS', N'FAIL') AS Result;

IF @DmlSuccesses = 0 OR @ApplicationSuccesses = 0
   OR @ApplicationFailures = 0 OR @NativeFailures = 0
    THROW 51251, 'FAIL - recent audit evidence does not yet contain every required outcome.', 1;
GO
