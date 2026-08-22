-- Set the restored database name and the standard deployment passwords.
:setvar TargetDatabaseName "SmartBankDB_RestoreDemo"
:setvar DbaLoginPassword "SBank!Dba_2026#Aisha"
:setvar ManagerDanielLoginPassword "SBank!Manager_2026#Daniel"
:setvar ManagerSitiLoginPassword "SBank!Manager_2026#Siti"
:setvar OfficerFaridLoginPassword "SBank!Officer_2026#Farid"
:setvar OfficerPriyaLoginPassword "SBank!Officer_2026#Priya"
:setvar CustomerAmeliaLoginPassword "SBank!Customer_2026#Amelia"
:setvar CustomerHafizLoginPassword "SBank!Customer_2026#Hafiz"
:setvar AuditorLoginPassword "SBank!Auditor_2026#Noor"

/*
    RESTORE DEMO LOGINS

    Run on the target SQL Server as sa after restoring SmartBankDB_RestoreDemo.
    Run once on a clean target instance in SQLCMD mode.
    The restored database already contains its users and role memberships.
    This script creates their server logins and reconnects the users to them.
    Change TargetDatabaseName above if your restored database has another name.
*/

-- Select the target server database.
USE [master];
GO

-- Create the standard SmartBank demonstration logins.
CREATE LOGIN [sb_dba_aisha] WITH PASSWORD = N'$(DbaLoginPassword)', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = [$(TargetDatabaseName)];
CREATE LOGIN [sb_manager_daniel] WITH PASSWORD = N'$(ManagerDanielLoginPassword)', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = [$(TargetDatabaseName)];
CREATE LOGIN [sb_manager_siti] WITH PASSWORD = N'$(ManagerSitiLoginPassword)', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = [$(TargetDatabaseName)];
CREATE LOGIN [sb_officer_farid] WITH PASSWORD = N'$(OfficerFaridLoginPassword)', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = [$(TargetDatabaseName)];
CREATE LOGIN [sb_officer_priya] WITH PASSWORD = N'$(OfficerPriyaLoginPassword)', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = [$(TargetDatabaseName)];
CREATE LOGIN [sb_customer_amelia] WITH PASSWORD = N'$(CustomerAmeliaLoginPassword)', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = [$(TargetDatabaseName)];
CREATE LOGIN [sb_customer_hafiz] WITH PASSWORD = N'$(CustomerHafizLoginPassword)', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = [$(TargetDatabaseName)];
CREATE LOGIN [sb_auditor_noor] WITH PASSWORD = N'$(AuditorLoginPassword)', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = [$(TargetDatabaseName)];
GO

-- Recreate the auditor's server-level audit access.
CREATE SERVER ROLE [SmartBankAuditReader] AUTHORIZATION [sa];
GRANT VIEW SERVER SECURITY AUDIT TO [SmartBankAuditReader];
ALTER SERVER ROLE [SmartBankAuditReader] ADD MEMBER [sb_auditor_noor];
GO

-- Reconnect the restored database users to the new server logins.
USE [$(TargetDatabaseName)];
GO
ALTER USER [sb_dba_aisha] WITH LOGIN = [sb_dba_aisha];
ALTER USER [sb_manager_daniel] WITH LOGIN = [sb_manager_daniel];
ALTER USER [sb_manager_siti] WITH LOGIN = [sb_manager_siti];
ALTER USER [sb_officer_farid] WITH LOGIN = [sb_officer_farid];
ALTER USER [sb_officer_priya] WITH LOGIN = [sb_officer_priya];
ALTER USER [sb_customer_amelia] WITH LOGIN = [sb_customer_amelia];
ALTER USER [sb_customer_hafiz] WITH LOGIN = [sb_customer_hafiz];
ALTER USER [sb_auditor_noor] WITH LOGIN = [sb_auditor_noor];
GO

-- Show that each restored database user now has a matching server login.
SELECT databaseUser.name AS DatabaseUser,
       serverLogin.name AS ServerLogin
FROM sys.database_principals AS databaseUser
LEFT JOIN sys.server_principals AS serverLogin
    ON serverLogin.sid = databaseUser.sid
WHERE databaseUser.name IN
(
    N'sb_dba_aisha', N'sb_manager_daniel', N'sb_manager_siti',
    N'sb_officer_farid', N'sb_officer_priya', N'sb_customer_amelia',
    N'sb_customer_hafiz', N'sb_auditor_noor'
)
ORDER BY databaseUser.name;
GO
