# SmartBank recovery module

All scripts must be run as `sa`.

For the presentation, follow [the SSMS-first runbook](../demo/SSMS_RUNBOOK.md). It uses Restore Database dialogs for encrypted full restore and PITR, with SQL for certificate preparation, scenario markers and validation. The full operation scripts below are alternative scripted workflows; do not execute them after completing the same restore through a dialog.

## 1. Encrypted full restore

Copy the following to directories readable by the second SQL Server service account:

- The selected encrypted full `.bak` file.
- `SmartBank_TDE_Certificate.cer` and `SmartBank_TDE_Certificate.pvk`.
- `SmartBank_Backup_Certificate.cer` and `SmartBank_Backup_Certificate.pvk`.

Run `operations/01_restore_encrypted_full.sql` on the second instance in SQLCMD mode. Supply every variable externally:

```powershell
sqlcmd -S "<second-instance>" -U sa -P "<sa-password>" -C -b -i "sql/recovery/operations/01_restore_encrypted_full.sql" -v TargetDatabaseName="SmartBankDB_RestoreDemo" SourceFullBackupFile="<server-side-bak-path>" TargetDataFile="<server-side-mdf-path>" TargetLogFile="<server-side-ldf-path>" TargetCertificateDirectory="<server-side-certificate-directory>" PathSeparator="\" TargetMasterKeyPassword="<new-target-master-key-password>" CertificateBackupPassword="<certificate-export-password>" RestoredDatabaseMasterKeyPassword="<source-database-master-key-password>"
```

Then run `validation/01_validate_encrypted_full_restore.sql` with the same `TargetDatabaseName`:

```powershell
sqlcmd -S "<second-instance>" -U sa -P "<sa-password>" -C -b -i "sql/recovery/validation/01_validate_encrypted_full_restore.sql" -v TargetDatabaseName="SmartBankDB_RestoreDemo"
```

The validation requires an ONLINE restored database, TDE, a service-master-key-protected database master key, non-empty core data, successful column decryption without displaying PII, `DBCC CHECKDB`, a valid transaction hash chain and reconciled account balances.

To demonstrate the restored database through the standard SmartBank logins, run `utilities/03_restore_demo_logins.sql` once on a clean target instance:

```powershell
sqlcmd -S "<second-instance>" -U sa -P "<sa-password>" -C -b -i "sql/recovery/utilities/03_restore_demo_logins.sql"
```

## 2. PITR

Run the following on the primary instance in this exact order:

1. `scenarios/01_pitr_capture_marker.sql` captures a pre-accident log backup and both UTC and SQL Server-local marker times. The marker applies to the entire database.
2. Update or delete one or two records in an audited business or demo table. Record the schema, table and key so the same rows can be shown after recovery. The safe fallback is:

   ```sql
   DELETE SmartBankDB.demo.RecoveryTarget WHERE RecoveryID = 1;
   DELETE SmartBankDB.demo.RecoveryTarget WHERE RecoveryID = 2;
   ```

3. `scenarios/02_pitr_capture_post_change_log.sql` refuses to continue unless an audited DELETE or UPDATE is present after the marker. It then captures and verifies the closing encrypted log backup.
4. `operations/02_restore_point_in_time.sql` selects the eligible full backup, optional differential and ordered log chain from `msdb`, verifies every selected medium, and restores a separate `SmartBankDB_PITR` database using `STOPAT`.
5. `validation/02_validate_pitr_restore.sql` checks the recovered copy's TDE encryption, integrity, ledger chain and account balances, and shows the audited source change. Use `sql/demo/03_availability/01_accidental_changes_recoverable.sql` to compare the exact live and recovered records selected in step 2.

The source database remains online throughout the restore because recovery targets a separate database. The scheduled five-minute transaction-log interval defines the normal-operation RPO.

## 3. Tail-log recovery drill

This optional drill restores the primary `SmartBankDB` in place, using its existing scheduled backup history. Finish other demonstrations first and rehearse it on an equivalent non-production instance.

1. Close other `SmartBankDB` sessions. Through any normal role or `sa`, manually perform one permitted audited `INSERT`, `UPDATE` or `DELETE`, display its effect, then disconnect that query. Any table covered by `audit.DmlAudit` is eligible.
2. Within two minutes, run the entire `operations/03_tail_log_recovery.sql` file once as primary `sa`.
3. Require PASS and inspect the discovered DML transaction, selected chain and restore history. The discovered transaction must be absent after recovery and the final selected backup must be the exact tail with `STOPAT + RECOVERY`.

The single operation performs all preflight, media verification, encrypted tail capture, full/differential/log restore and validation. Its initial target is SQL Server time minus two minutes. It dynamically discovers the latest DML audit row and all audit rows sharing its actor and database transaction; procedure-level application metadata is included when a correlation ID exists but is not required. When a scheduled log ended inside the recovery window, the operation can move the target just after that log only while remaining before the audited change; otherwise it stops before tail capture. The manual destructive action is intentionally absent from the recovery SQL.

The online-database tail uses `NORECOVERY`; `NO_TRUNCATE` is reserved for an offline or damaged database. The operation overwrites `SmartBankDB`, so it also discards other legitimate work after `STOPAT`. If a failure occurs after tail capture, the database can remain in `RESTORING`; retain the reported media and repair the restore sequence rather than redeploying.

## 4. Temporal row-recovery

Run Step 1 of `scenarios/03_temporal_row_recovery.sql` on the primary instance, keep that SSMS window open, let the lecturer manually update customer `C00012` in another window, then run Step 2. The script retrieves the version at its saved pre-change time with `FOR SYSTEM_TIME AS OF` and restores all customer columns.

Then run `validation/03_validate_temporal_recovery.sql`. It uses the manual-change and recovery audit records to prove that:

- the manual and restorative updates were both audited;
- the current row matches the pre-accident business values;
- the manually changed version remains in temporal history; and
- no whole-database restore was required.

## 5. Cleanup

Cleanup is intentionally separate and confirmation-gated. Review the target names first, then run:

```powershell
sqlcmd -S "<instance>" -U sa -P "<sa-password>" -C -b -i "sql/recovery/utilities/01_cleanup_validation_databases.sql" -v ConfirmCleanup="DROP_RECOVERY_VALIDATION_DATABASES" PitrDatabaseName="SmartBankDB_PITR" RestoreValidationDatabaseName="SmartBankDB_RestoreDemo"
```
