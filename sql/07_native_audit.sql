USE [master];
GO
SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'SmartBank_ServerAudit')
BEGIN
    DECLARE @CreateAuditSql nvarchar(max) =
        N'CREATE SERVER AUDIT SmartBank_ServerAudit
          TO FILE
          (
              FILEPATH = N''' + REPLACE(N'$(AuditDirectory)$(PathSeparator)', N'''', N'''''') + N''',
              MAXSIZE = 100 MB,
              MAX_ROLLOVER_FILES = 50,
              RESERVE_DISK_SPACE = OFF
          )
          WITH (QUEUE_DELAY = 1000, ON_FAILURE = FAIL_OPERATION);';
    EXEC sys.sp_executesql @CreateAuditSql;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'SmartBank_ServerAuditSpecification')
BEGIN
    CREATE SERVER AUDIT SPECIFICATION SmartBank_ServerAuditSpecification
    FOR SERVER AUDIT SmartBank_ServerAudit
        ADD (AUDIT_CHANGE_GROUP),
        ADD (FAILED_LOGIN_GROUP),
        ADD (SUCCESSFUL_LOGIN_GROUP),
        ADD (LOGOUT_GROUP),
        ADD (SERVER_PRINCIPAL_CHANGE_GROUP),
        ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP),
        ADD (SERVER_OBJECT_PERMISSION_CHANGE_GROUP)
    WITH (STATE = ON);
END;
ELSE
    ALTER SERVER AUDIT SPECIFICATION SmartBank_ServerAuditSpecification WITH (STATE = ON);
GO
ALTER SERVER AUDIT SmartBank_ServerAudit WITH (STATE = ON);
GO

USE [$(DatabaseName)];
GO
IF EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = N'SmartBank_DatabaseAuditSpecification')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION SmartBank_DatabaseAuditSpecification WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION SmartBank_DatabaseAuditSpecification;
END;

CREATE DATABASE AUDIT SPECIFICATION SmartBank_DatabaseAuditSpecification
FOR SERVER AUDIT SmartBank_ServerAudit
    ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),
    ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
    ADD (DATABASE_OBJECT_PERMISSION_CHANGE_GROUP),
    ADD (SCHEMA_OBJECT_PERMISSION_CHANGE_GROUP),
    ADD (DATABASE_OBJECT_CHANGE_GROUP),
    ADD (SCHEMA_OBJECT_CHANGE_GROUP),
    ADD (SELECT, INSERT, UPDATE, DELETE ON SCHEMA::core BY public),
    ADD (SELECT, INSERT, UPDATE, DELETE ON SCHEMA::sec BY public),
    ADD (EXECUTE ON SCHEMA::api BY public),
    ADD (SELECT ON SCHEMA::audit BY public)
WITH (STATE = ON);
GO

CREATE OR ALTER PROCEDURE audit.usp_ReadNativeAudit
    @StartTime datetime2(3) = NULL,
    @EndTime datetime2(3) = NULL,
    @OnlyFailures bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @AuditPattern nvarchar(4000) =
        (SELECT ConfigValue FROM ops.Configuration WHERE ConfigKey = N'AuditDirectory') +
        (SELECT ConfigValue FROM ops.Configuration WHERE ConfigKey = N'PathSeparator') + N'*.sqlaudit';

    SET @StartTime = COALESCE(@StartTime, DATEADD(DAY, -7, SYSUTCDATETIME()));
    SET @EndTime = COALESCE(@EndTime, SYSUTCDATETIME());

    SELECT event_time AS EventTimeUtc,
           action_id AS ActionID,
           succeeded AS Succeeded,
           session_id AS SessionID,
           server_principal_name AS ServerPrincipal,
           database_principal_name AS DatabasePrincipal,
           database_name AS DatabaseName,
           schema_name AS SchemaName,
           object_name AS ObjectName,
           statement AS StatementText,
           application_name AS ApplicationName,
           client_ip AS ClientAddress,
           additional_information AS AdditionalInformation,
           file_name AS AuditFile
    FROM sys.fn_get_audit_file(@AuditPattern, DEFAULT, DEFAULT)
    WHERE event_time >= @StartTime
      AND event_time < @EndTime
      AND (@OnlyFailures = 0 OR succeeded = 0)
      AND (database_name = DB_NAME() OR action_id IN ('LGIS', 'LGIF', 'LGO'))
    ORDER BY event_time DESC, sequence_number DESC;
END;
GO

CREATE OR ALTER VIEW audit.vw_AuditMatrix
AS
    SELECT *
    FROM (VALUES
        ('Login success', 'SQL Server Audit', 'SUCCESSFUL_LOGIN_GROUP', 'Server audit file', 'Server principal, client IP, application, UTC time'),
        ('Login failure', 'SQL Server Audit', 'FAILED_LOGIN_GROUP', 'Server audit file', 'Failed principal, client IP, application, UTC time'),
        ('Logout', 'SQL Server Audit', 'LOGOUT_GROUP', 'Server audit file', 'Server principal, session and UTC time'),
        ('Successful DML', 'DML triggers + SQL Server Audit', 'INSERT/UPDATE/DELETE', 'audit.DmlAudit + server audit file', 'Before/after JSON, actor, host, IP, transaction and correlation IDs'),
        ('Invalid or denied DML', 'SQL Server Audit', 'INSERT/UPDATE/DELETE', 'Server audit file', 'Succeeded=0, statement, actor, object and client context'),
        ('Stored procedure outcome', 'Application event logging + SQL Server Audit', 'EXECUTE', 'audit.ApplicationEvent + server audit file', 'Success/failure, safe error, target and correlation ID'),
        ('DDL', 'SQL Server Audit', 'SCHEMA_OBJECT_CHANGE_GROUP', 'Server audit file', 'CREATE/ALTER/DROP statement, actor and object'),
        ('Database user/role change', 'SQL Server Audit', 'DATABASE_PRINCIPAL_CHANGE_GROUP / DATABASE_ROLE_MEMBER_CHANGE_GROUP', 'Server audit file', 'Principal, role, statement and actor'),
        ('Permission change', 'SQL Server Audit', 'SCHEMA_OBJECT_PERMISSION_CHANGE_GROUP / DATABASE_OBJECT_PERMISSION_CHANGE_GROUP / SERVER_OBJECT_PERMISSION_CHANGE_GROUP', 'Server audit file', 'GRANT/DENY/REVOKE statement and actor'),
        ('Audit configuration change', 'SQL Server Audit', 'AUDIT_CHANGE_GROUP', 'Server audit file', 'Audit tampering attempt or configuration change')
    ) AS matrix (EventCategory, Mechanism, AuditAction, EvidenceLocation, CapturedEvidence);
GO
