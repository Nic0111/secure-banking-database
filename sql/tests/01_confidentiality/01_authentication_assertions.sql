-- Connect as: sa
USE [master];
GO

-- Verify that every demonstration login exists and enforces password policy.
IF (SELECT COUNT(*) FROM sys.sql_logins WHERE name IN
    (N'sb_dba_aisha', N'sb_dba_kavitha', N'sb_manager_daniel', N'sb_manager_siti',
     N'sb_officer_farid', N'sb_officer_priya', N'sb_customer_amelia',
     N'sb_customer_hafiz', N'sb_auditor_noor')) <> 9
    THROW 51100, 'FAIL: one or more SmartBank logins are missing.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.sql_logins
    WHERE name IN
        (N'sb_dba_aisha', N'sb_dba_kavitha', N'sb_manager_daniel', N'sb_manager_siti',
         N'sb_officer_farid', N'sb_officer_priya', N'sb_customer_amelia',
         N'sb_customer_hafiz', N'sb_auditor_noor')
      AND (is_policy_checked = 0 OR default_database_name <> N'SmartBankDB')
)
    THROW 51101, 'FAIL: a SmartBank login does not enforce policy or use SmartBankDB.', 1;

SELECT name AS LoginName, is_policy_checked, is_expiration_checked, default_database_name
FROM sys.sql_logins
WHERE name IN
    (N'sb_dba_aisha', N'sb_dba_kavitha', N'sb_manager_daniel', N'sb_manager_siti',
     N'sb_officer_farid', N'sb_officer_priya', N'sb_customer_amelia',
     N'sb_customer_hafiz', N'sb_auditor_noor')
ORDER BY name;
GO
