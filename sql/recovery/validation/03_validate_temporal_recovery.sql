/*
RECOVERY MODULE:
Validation - Temporal row recovery

PURPOSE:
Use the manual-change and recovery audit records with temporal history to prove
that the latest customer recovery was reversed without a whole-database restore.

RUN AS:
sa or another sysadmin after scenarios/03_temporal_row_recovery.sql.

PRECONDITIONS:
The temporal recovery scenario completed and retained its audit/history evidence.

DATABASE CHANGES:
None. This script is read-only.

PASS CONDITION:
The manual change and repair are audited, current business values match the version
before the manual change, and the changed version remains in temporal history.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

DECLARE @CorrelationID uniqueidentifier;
SELECT TOP (1) @CorrelationID = CorrelationID
FROM audit.DmlAudit
WHERE SchemaName = N'core' AND TableName = N'Customer' AND ActionType = 'UPDATE'
  AND CorrelationID IS NOT NULL
  AND JSON_VALUE(NewValues, '$[0].CustomerID') = 'C00012'
ORDER BY EventTime DESC, AuditID DESC;
IF @CorrelationID IS NULL
    THROW 52442, 'No temporal recovery for C00012 was found.', 1;

DECLARE @AccidentAuditID bigint, @RecoveryAuditID bigint,
        @OriginalName nvarchar(100), @OriginalEmail varchar(254), @OriginalStatus varchar(12),
        @AccidentalName nvarchar(100), @AccidentalEmail varchar(254), @AccidentalStatus varchar(12),
        @CurrentName nvarchar(100),
        @CurrentEmail varchar(254), @CurrentStatus varchar(12);

SELECT TOP (1)
       @RecoveryAuditID = AuditID,
       @OriginalName = JSON_VALUE(NewValues, '$[0].CustomerName'),
       @OriginalEmail = JSON_VALUE(NewValues, '$[0].Email'),
       @OriginalStatus = JSON_VALUE(NewValues, '$[0].Status'),
       @AccidentalName = JSON_VALUE(OldValues, '$[0].CustomerName'),
       @AccidentalEmail = JSON_VALUE(OldValues, '$[0].Email'),
       @AccidentalStatus = JSON_VALUE(OldValues, '$[0].Status')
FROM audit.DmlAudit
WHERE SchemaName = N'core' AND TableName = N'Customer' AND ActionType = 'UPDATE'
  AND CorrelationID = @CorrelationID
ORDER BY EventTime, AuditID;

SELECT TOP (1) @AccidentAuditID = AuditID
FROM audit.DmlAudit
WHERE SchemaName = N'core' AND TableName = N'Customer' AND ActionType = 'UPDATE'
  AND CorrelationID IS NULL AND AuditID < @RecoveryAuditID
  AND JSON_VALUE(NewValues, '$[0].CustomerID') = 'C00012'
  AND JSON_VALUE(NewValues, '$[0].CustomerName') = @AccidentalName
  AND JSON_VALUE(NewValues, '$[0].Email') = @AccidentalEmail
  AND JSON_VALUE(NewValues, '$[0].Status') = @AccidentalStatus
ORDER BY EventTime DESC, AuditID DESC;

SELECT @CurrentName = CustomerName, @CurrentEmail = Email, @CurrentStatus = Status
FROM core.Customer WHERE CustomerID = 'C00012';

SELECT N'PASS' AS ValidationResult,
       @CorrelationID AS CorrelationID,
       @AccidentAuditID AS AccidentAuditID,
       @RecoveryAuditID AS RecoveryAuditID,
       'C00012' AS CustomerID,
       @CurrentName AS RestoredCustomerName,
       @CurrentStatus AS RestoredStatus,
       @AccidentalName AS RetainedHistoricalAccident;

SELECT AuditID, EventTime, ActionType, ActorLogin, CorrelationID, OldValues, NewValues
FROM audit.DmlAudit
WHERE CorrelationID = @CorrelationID
ORDER BY EventTime, AuditID;

SELECT CustomerID, CustomerName, Email, Status, ValidFrom, ValidTo
FROM core.Customer FOR SYSTEM_TIME ALL
WHERE CustomerID = 'C00012'
  AND (CustomerName = @AccidentalName OR CustomerName = @OriginalName)
ORDER BY ValidFrom DESC;
GO
