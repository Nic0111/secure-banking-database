:on error exit

:setvar DatabaseName "SmartBankDB"
:setvar AnalyticsDatabaseName "SmartBankAnalyticsDB"
:setvar BackupDirectory "C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER02\MSSQL\Backup\SmartBankBackup"
:setvar AuditDirectory "C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER02\MSSQL\Backup\SmartBankAudit"
:setvar CertificateDirectory "C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER02\MSSQL\Backup\SmartBankKeys"
:setvar PathSeparator "\"
:setvar MasterKeyPassword "SBank!MasterKey_2026#LocalOnly"
:setvar CertificateBackupPassword "SBank!Certificate_2026#LocalOnly"
:setvar DbaLoginPassword "SBank!Dba_2026#Aisha"
:setvar DbaKavithaLoginPassword "SBank!Dba_2026#Kavitha"
:setvar ManagerDanielLoginPassword "SBank!Manager_2026#Daniel"
:setvar ManagerSitiLoginPassword "SBank!Manager_2026#Siti"
:setvar OfficerFaridLoginPassword "SBank!Officer_2026#Farid"
:setvar OfficerPriyaLoginPassword "SBank!Officer_2026#Priya"
:setvar CustomerAmeliaLoginPassword "SBank!Customer_2026#Amelia"
:setvar CustomerHafizLoginPassword "SBank!Customer_2026#Hafiz"
:setvar AuditorLoginPassword "SBank!Auditor_2026#Noor"
:setvar DemoTransactionPin "482731"

PRINT N'=== SmartBank secure database deployment ===';
:r reset.sql
:r implementation/00_environment.sql
:r implementation/01_schema.sql
:r implementation/02_cryptography.sql
:r implementation/03_row_level_security.sql
:r implementation/04_audit_tables_and_triggers.sql
:r implementation/05_api.sql
:r implementation/06_seed_data.sql
:r implementation/07_native_audit.sql
:r implementation/08_principals_and_permissions.sql
:r implementation/09_backup_automation.sql
:r implementation/10_static_masking.sql

PRINT N'=== Deployment completed successfully ===';
GO
