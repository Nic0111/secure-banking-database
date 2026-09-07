# SmartBank presentation runbook — SSMS first

Use SSMS dialogs for administration and inspection. Use query windows for SmartBank procedures, evidence queries, certificate setup and temporal recovery. Encrypted full restore and PITR use **Restore Database** here. The optional tail-log drill uses its dynamic operation script so the complete LSN chain and fixed two-minute `STOPAT` are selected consistently from `msdb`.

Paths below are relative to `sql/`. Follow this presentation order rather than folder numbering. Reviewed against the repository and Microsoft documentation on 5 September 2026. Rehearsal on the actual Windows instances remains outstanding.

## 1. Prepare before presentation day

1. Establish the golden baseline at least three completed calendar days before presenting backup history. `deploy.sql` invokes `reset.sql`, which drops and rebuilds SmartBank databases, jobs and demo logins. Do not redeploy immediately before presenting.
2. Deployment remains a SQLCMD script. To run it in SSMS, enable **Query > SQLCMD Mode** and ensure all `:r sql/...` includes resolve from the repository root on the Windows computer. Opening the file alone does not establish that working directory; use an unsaved local copy with absolute include paths if needed.
3. Confirm **SQL Server Agent** is running and the three SmartBank backup jobs have genuine successful history.
4. Rehearse the role assertions and recovery separately. Tests and integrity demos can change the baseline; finish these before establishing the intended presentation state.
5. Prepare a compatible second SQL Server instance. Use Windows file management to copy the selected full backup and both certificate/private-key pairs to directories readable by its SQL Server service account.
6. For a short presentation, complete encrypted restore beforehand and validate it live. If demonstrating the actual restore live, prepare only the files and certificates beforehand.
7. Copy-based restores need unused targets: `SmartBankDB_RestoreDemo` on the second instance and `SmartBankDB_PITR` on the primary. Arrange explicit cleanup of rehearsal copies before the session and never reuse source physical-file paths for those copies. The optional tail-log drill is different: it explicitly restores `SmartBankDB` in place and must be rehearsed separately.

## 2. Open connections and check the baseline

Use **Connect > Database Engine** with SQL Server Authentication to open primary-instance connections for `sa`, Daniel, Farid, Aisha, Amelia and Noor. Keep Siti, Priya and Hafiz available for comparisons. Open a separate second-instance `sa` connection. Create queries from the correct Object Explorer connection and check the server/login before executing.

Run `demo/00_preflight_and_baseline.sql` as primary `sa`. Inspect database state, users, row counts and jobs. It displays information rather than rejecting every invalid baseline. Confirm `S00008` and `ADEMO00001` have not already been created by rehearsal, and recovery-target rows 1 and 2 exist.

Run examples containing expected errors in selected logical blocks: allowed action, expected denial, then next action. Explicitly execute cleanup after an error. Unexpected errors are not successful evidence. Fresh authenticated connections, rather than impersonation, prove actual login identity.

## 3. Authentication and confidentiality

1. As `sa`, expand **Security > Logins**. Inspect a login's **Properties > User Mapping** and its SmartBank roles; close with Cancel.
2. Run `demo/01_confidentiality/01_all_users_authenticated.sql` as `sa`, then through fresh actor connections to show the actual login and role.
3. Attempt one incorrect password through the SSMS connection dialog. Show the failure; inspect its audit event later.
4. Under **SmartBankDB > Security > Roles > Database Roles**, inspect role membership/securables if needed. Configuration is followed by actual allowed/denied operations.
5. Execute the following confidentiality scripts. Use queries because they exercise the protected application's actual views and procedures.

| Connection | File under `demo/01_confidentiality/` | Evidence |
|---|---|---|
| Farid | `02_all_authenticated_users_staff_directory.sql` | Shared directory, then base-table denial |
| Daniel | `03_bank_manager_visibility.sql` | Own profile, branch staff and permitted customer data, then denial |
| Farid | `04_bank_officer_visibility.sql` | Officer profile and permitted views, then denial |
| Aisha | `05_dba_visibility.sql` | Own profile/directory, then customer-data denial |
| Amelia | `06_customer_visibility.sql` | Own decrypted profile, accounts and transactions, then denial |

Repeat through Siti/Hafiz if asked to compare identities. Do not add permissions merely to make a GUI page work.

## 4. Integrity, hiring and audit

| Order | Connection | Action |
|---:|---|---|
| 1 | Aisha | `demo/02_integrity/01_dba_table_management_only.sql`: execute CREATE/ALTER, inspect columns, run denied INSERT separately, then explicitly run DROP TABLE. |
| 2 | Daniel | `demo/02_integrity/02_manager_manages_staff.sql`: complete successful updates and hire `S00008`, then execute the invalid examples individually. |
| 3 | Primary sa | Complete the new officer login procedure below immediately after hiring. |
| 4 | Farid | `demo/02_integrity/03_officer_manages_customer_accounts.sql`: open `ADEMO00001`, freeze/show it, return it to ACTIVE, then show denied balance manipulation. |
| 5 | Farid | `demo/02_integrity/04_staff_updates_own_record_except_salary.sql`: update own profile, then show denied salary update. |
| 6 | Amelia | `demo/02_integrity/05_customer_transactions.sql` in SQLCMD Mode: valid transactions, then invalid cases. Include the `@DemoPin` DECLARE with each separately executed block that uses it; local variables do not persist between executions. |
| 7 | Primary sa, optional | Complete `demo/90_permission_change_extension.sql` if asked: temporary user, grant, revoke, cleanup and audit. |
| 8 | Noor | Run `demo/02_integrity/06_all_valid_invalid_manipulations_logged.sql` once after all preceding changes. |

### Create the new officer login through SSMS

1. As primary `sa`, choose **Security > Logins > New Login**. Name it `sb_officer_demo`, choose SQL Server Authentication and enter the prepared password privately. Set default database to `SmartBankDB`. Keep password policy enabled; avoid requiring a first-login password change for the prepared demo account.
2. In **User Mapping**, map `SmartBankDB` to username `sb_officer_demo`, selecting `rl_officer` and `rl_authenticated`. Leave server roles at default `public`. Save.
3. Open `demo/02_integrity/07_sa_wires_new_officer_login.sql`. Select from `USE [SmartBankDB];` through the final `msdb` denial section, including GO separators, and execute. Skip the opening master/login-creation batch. The remaining SQL validates the active officer, supplies the application-specific `sec.PrincipalMap` mapping and denies backup-catalog access. GUI login creation alone does not supply that mapping.
4. Connect freshly as `sb_officer_demo` to `SmartBankDB`. Execute `EXEC api.usp_GetMyStaffProfile;`, then separately `SELECT * FROM core.Staff;` to show the denial.

The existing transaction file contains a PIN declaration, and administrative files contain demo passwords. Prepare private declarations before projecting and exclude them from screenshots.

For native audit inspection, primary `sa` can open **Security > Audits > [configured audit] > View Audit Logs** and filter by time/actor. Noor's query proves the auditor's own access. Refresh after the audit flush interval if the latest event is not yet visible.

## 5. Establish backup and RPO evidence

1. As primary `sa`, open **SQL Server Agent > Jobs**. Inspect each SmartBank job's **Properties > Schedules**: full daily at 01:00, differential every six hours, log every five minutes. Close without saving.
2. Right-click each job and choose **View History**. Show actual successful runs and dates.
3. Run `demo/03_availability/02_rpo_evidence.sql`, followed by `demo/03_availability/03_automated_backup_evidence.sql`, for log timestamps and the three completed calendar days.
4. Describe five minutes as the scheduled interval. Failed/late jobs can increase actual exposure. These demo queries display timestamps/counts; they do not calculate the largest backup gap or independently verify all stored media.

## 6. Encrypted full restore through the SSMS dialog

Use the **second instance as sa**. If prepared beforehand, show validation live and identify the restore as completed in advance.

### Certificate preparation in a query window

1. On the primary, run `recovery/utilities/02_show_latest_encrypted_full_backup.sql` to identify the actual selected backup.
2. Copy that full backup and `SmartBank_TDE_Certificate.cer/.pvk` plus `SmartBank_Backup_Certificate.cer/.pvk` to the target server.
3. On the target, open `recovery/operations/01_restore_encrypted_full.sql` in SQLCMD Mode. Review its existing `:setvar` declarations in an unsaved copy: actual backup, new target file paths, certificate directory and passwords. The dated default backup path may be stale; in-file declarations must be reviewed directly.
4. Select from the start of the file through `RESTORE FILELISTONLY FROM DISK = @BackupFile;` only. Stop before the comment beginning `The source implementation creates one data file`. Execute this selection to prepare certificates and verify/inspect the backup. Do not execute the full operation file when using the dialog.

### Restore and validate

1. On the second instance, right-click **Databases > Restore Database**.
2. **General:** select **Source: Device > ... > Add**, choose the copied full backup, and set **Destination: Database** to `SmartBankDB_RestoreDemo`.
3. **Files:** set every **Restore As** path to a new target file, using `SmartBankDB_RestoreDemo.mdf` and `SmartBankDB_RestoreDemo_log.ldf` in writable target-server directories.
4. **Options:** select **RESTORE WITH RECOVERY**, leave **Overwrite the existing database (WITH REPLACE)** unchecked, and disable **Take tail-log backup before restore** if offered.
5. Review the backup, destination and files, click **OK**, then refresh Object Explorer.
6. In a private target query, re-protect the restored database master key using the source database master-key password:

```sql
USE [SmartBankDB_RestoreDemo];
OPEN MASTER KEY DECRYPTION BY PASSWORD = '<source-database-master-key-password>';
ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY;
CLOSE MASTER KEY;
```

7. Open `recovery/validation/01_validate_encrypted_full_restore.sql` in SQLCMD Mode, check its `TargetDatabaseName` declaration, and run it on the target. Require PASS for online state, TDE, key protection, decryption, database integrity, ledger and balances.

If demonstrating restored role logins, prepare `recovery/utilities/03_restore_demo_logins.sql` privately once on a clean target. It remaps restored users and supplies auditor permissions; creating server logins alone is insufficient. Its unconditional CREATE LOGIN statements must not be rerun against existing logins.

## 7. Live PITR through Timeline

Run the entire segment on the **primary instance as sa**. Avoid unrelated writes between marker and comparison.

1. Show `demo.RecoveryTarget` rows 1 and 2 and confirm they exist. This table avoids business-ledger and foreign-key complications.
2. Run `recovery/scenarios/01_pitr_capture_marker.sql`. Record `MarkerTimeServer` and check the pre-marker backup ID/file are populated. The supplied script preserves the project's marker/backup evidence.
3. Wait several seconds beyond the marker before the accident. In Object Explorer, open **SmartBankDB > Tables > demo.RecoveryTarget > Edit Top 200 Rows**. Identify records by `RecoveryID`, select the row headers for IDs 1 and 2, delete and confirm, then refresh. The lecturer can perform this action. Alternatively use the two DELETE statements in `recovery/README.md`. Record the exact keys.
4. Run `recovery/scenarios/02_pitr_capture_post_change_log.sql`. Require its audited change and verified closing log-backup result.
5. Choose **Databases > Restore Database**. Set **Source: Database = SmartBankDB** and **Destination: Database = SmartBankDB_PITR**.
6. Open **Timeline > Specific date and time**. Enter `MarkerTimeServer` using SQL Server's local time, not `MarkerTimeUtc` or the client computer's clock. If the dialog accepts only whole seconds, round the marker down to that second; ensure the before-image was committed earlier than that selected second. The deliberate pause keeps the accident later than the target.
7. Check that the selected plan contains an eligible full backup, optional matching differential and required logs through the selected time. Stop if media are unavailable or the time falls outside the chain; do not move the time past the accident to proceed.
8. **Files:** redirect every file to separate `SmartBankDB_PITR.mdf` and `SmartBankDB_PITR_log.ldf` paths in writable server directories.
9. **Options:** select **RESTORE WITH RECOVERY**, leave **WITH REPLACE** unchecked and uncheck **Take tail-log backup before restore**, including any option to leave the source restoring. The closing log backup already covers this drill. Do not close connections to the source.
10. Review destination/time and click **OK**. Refresh Object Explorer; both source and restored copy should be online. Do not also execute `recovery/operations/02_restore_point_in_time.sql`, which is the alternative scripted restore.
11. Run `recovery/validation/02_validate_pitr_restore.sql` and require PASS. Immediately run `demo/03_availability/01_accidental_changes_recoverable.sql`; its default queries compare IDs 1 and 2. If different records were chosen, use the same table/key filter in both comparisons.
12. Show the actual dialog restore point with this query:

```sql
SELECT TOP (1) destination_database_name, restore_date, stop_at, recovery
FROM msdb.dbo.restorehistory
WHERE destination_database_name = N'SmartBankDB_PITR'
  AND restore_type = 'L'
ORDER BY restore_history_id DESC;
```

The validator checks restored integrity and source audit evidence; it does not assert equality of arbitrary lecturer-selected rows or the exact dialog STOPAT. The row comparison and restore history complete that proof. The recovered rows are in the copy; the source accident remains until a separate repair is deliberately performed.

## 8. Optional one-file tail-log recovery of the primary database

This is the deliberately destructive availability demonstration: it captures the tail and restores `SmartBankDB` in place from its existing scheduled backup chain. Complete the other primary-database demonstrations first, confirm successful full/differential/log job history, and rehearse this operation on an equivalent non-production instance before presenting it.

1. Close every other primary-instance `SmartBankDB` query and disconnect application sessions. Keep only the role connection that will demonstrate the accident and a primary `sa` window ready to run the recovery file.
2. Through any normal SmartBank role or `sa`, manually perform one permitted audited `INSERT`, `UPDATE` or `DELETE` and inspect its result. It may affect any table covered by `audit.DmlAudit`; no particular actor, procedure, table, action type or record key is required. Close or disconnect that query immediately afterwards.
3. Within two minutes of the manual action, run the whole `recovery/operations/03_tail_log_recovery.sql` file once as primary `sa`. It discovers the newest DML audit row and every row in the same database transaction, starts with server time minus two minutes, verifies the existing encrypted/checksummed full, compatible differential and regular log media, captures a uniquely named encrypted tail with `NORECOVERY`, restores the entire chain, and performs all validation before reporting PASS. There are no separate preparation, capture or validation files for this drill.
4. Review all result sets. Require PASS, confirm `AppliedStopAt` is earlier than `AccidentTimeServer`, inspect the dynamically captured actor/table/action/before-and-after evidence, confirm the final selected-chain row is `TAIL LOG / STOPAT + RECOVERY`, and inspect the matching `msdb.dbo.restorehistory` sequence.

The initial target is `GETDATE() - 2 minutes`. If a scheduled log finished inside that interval, the operation moves the target just after that regular log so the tail remains the final log that contains the recovery point. It refuses to start if that adjustment would reach or cross the discovered accident, if required media are missing, or if any regular log already finished at or after the accident. This healthy online-database demonstration uses `NORECOVERY`; do not add `NO_TRUNCATE`. Because the operation overwrites the primary database, legitimate work after the selected `STOPAT` is also discarded. If an unexpected error occurs after tail capture, retain the reported backup media and repair the restore sequence; the database can remain in `RESTORING`.

## 9. Temporal recovery of one source row

1. As primary `sa`, open `recovery/scenarios/03_temporal_row_recovery.sql`. Select the setup and **Step 1** only, stopping at the `Stop here` comment. Execute and keep the connection open because `#TemporalRecoveryPoint` belongs to it.
2. In another primary `sa` window, use **core.Customer > Edit Top 200 Rows**, locate `CustomerID = C00012`, and change only `CustomerName` to a distinct demonstration value. Move off the row to commit. Do not edit IDs, encrypted bytes or period columns. Use the scenario's example UPDATE if the grid cannot edit the temporal table.
3. Return to the original query connection and execute only **Step 2** through the end. Never rerun Step 1 after the change.
4. Immediately run `recovery/validation/03_validate_temporal_recovery.sql`. Show the repaired source row, audit events and retained historical changed version.

Explain the visible difference: PITR recovered a database copy; temporal recovery repaired this row in the source.

## 10. Close and retain evidence

Run `demo/99_consolidated_evidence.sql` as primary `sa`. Its database list is local to that instance, so show `SmartBankDB_RestoreDemo` and its validation separately on the second instance. Its absence from the primary query is expected.

Keep restore copies until marking is complete. The integrity scripts create staff/account records and transactions, while PITR leaves the source accident in place. Do not repeat the entire sequence blindly. Establish a deliberate baseline before another full run while preserving sufficient time for the required backup evidence.

## References and rehearsal

- [Microsoft: Restore a Database Backup Using SSMS](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/restore-a-database-backup-using-ssms?view=sql-server-ver17)
- [Microsoft: Restore a SQL Server Database to a Point in Time](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/restore-a-sql-server-database-to-a-point-in-time-full-recovery-model?view=sql-server-ver17)
- [Microsoft: Tail-log backups](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/tail-log-backups-sql-server?view=sql-server-ver17)

Rehearse the actual SSMS dialog labels, target file/key access, Timeline precision, all restore validations, exact before/after rows and switching between the two instances. This document records a reviewed workflow, not a successful live execution.
