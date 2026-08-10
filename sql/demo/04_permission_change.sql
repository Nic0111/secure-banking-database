-- Run as sa. This reversible demo change is captured by SQL Server Audit.
USE [SmartBankDB];
GO

DECLARE @DemoStart datetime2(3) = DATEADD(SECOND, -2, SYSUTCDATETIME());

IF USER_ID(N'sb_demo_temporary_user') IS NULL
    CREATE USER [sb_demo_temporary_user] WITHOUT LOGIN;
ALTER ROLE rl_authenticated ADD MEMBER [sb_demo_temporary_user];
GRANT SELECT ON OBJECT::api.vw_StaffDirectory TO [sb_demo_temporary_user];
REVOKE SELECT ON OBJECT::api.vw_StaffDirectory FROM [sb_demo_temporary_user];
ALTER ROLE rl_authenticated DROP MEMBER [sb_demo_temporary_user];
DROP USER [sb_demo_temporary_user];

WAITFOR DELAY '00:00:02';
EXEC audit.usp_ReadNativeAudit @StartTime = @DemoStart, @EndTime = NULL, @OnlyFailures = 0;
GO
