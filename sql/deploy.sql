:on error exit

-- The coursework database names are fixed so every demo/recovery script agrees.
-- Paths and secrets are intentionally not defined here: supply them with sqlcmd -v.
:setvar DatabaseName "SmartBankDB"
:setvar AnalyticsDatabaseName "SmartBankAnalyticsDB"

PRINT N'=== SmartBank secure database deployment ===';
:r sql/00_environment.sql
:r sql/01_schema.sql
:r sql/02_cryptography.sql
:r sql/03_row_level_security.sql
:r sql/04_audit_tables_and_triggers.sql
:r sql/05_api.sql
:r sql/06_seed_data.sql
:r sql/07_native_audit.sql
:r sql/08_principals_and_permissions.sql
:r sql/09_backup_automation.sql
:r sql/10_static_masking.sql

PRINT N'=== Deployment completed successfully ===';
GO
