# SmartBank recovery module

This module contains executable recovery workflows for the assignment's availability requirements. It proves that encrypted backups are usable, accidental changes can be recovered to a chosen point in time, row-level mistakes can be repaired from temporal history, and each result can be validated independently.

The folders deliberately separate responsibilities:

| Folder | Responsibility | Normal data effect |
|---|---|---|
| `operations` | Privileged restore mechanics | Creates a separate restored database |
| `scenarios` | Controlled accidental-change drills | Changes demonstration data and then captures/reverses it as stated |
| `validation` | Read-only acceptance evidence | None |
| `utilities` | Explicit maintenance | Drops only named validation databases after confirmation |

All scripts must be run as `sa` or another `sysadmin`. Do not run recovery operations through an application login. SQL Server Agent must be running for the scheduled five-minute RPO evidence, although the scenario scripts also capture explicit log backups to close a deterministic demonstration chain.

## 1. Cross-instance encrypted full restore

Copy the following to directories readable by the second SQL Server service account:

- The selected encrypted full `.bak` file.
- `SmartBank_TDE_Certificate.cer` and `SmartBank_TDE_Certificate.pvk`.
- `SmartBank_Backup_Certificate.cer` and `SmartBank_Backup_Certificate.pvk`.

Keep certificate/private-key media separate from database backup media outside this isolated coursework environment.

Run `operations/01_restore_encrypted_full.sql` on the second instance in SQLCMD mode. Supply every variable externally:

```powershell
sqlcmd -S "<second-instance>" -U sa -P "<sa-password>" -C -b -i "sql/recovery/operations/01_restore_encrypted_full.sql" -v TargetDatabaseName="SmartBankDB_RestoreDemo" SourceFullBackupFile="<server-side-bak-path>" TargetDataFile="<server-side-mdf-path>" TargetLogFile="<server-side-ldf-path>" TargetCertificateDirectory="<server-side-certificate-directory>" PathSeparator="\" TargetMasterKeyPassword="<new-target-master-key-password>" CertificateBackupPassword="<certificate-export-password>" RestoredDatabaseMasterKeyPassword="<source-database-master-key-password>"
```

Then run `validation/01_validate_encrypted_full_restore.sql` with the same `TargetDatabaseName`:

```powershell
sqlcmd -S "<second-instance>" -U sa -P "<sa-password>" -C -b -i "sql/recovery/validation/01_validate_encrypted_full_restore.sql" -v TargetDatabaseName="SmartBankDB_RestoreDemo"
```

The validation requires an ONLINE restored database, TDE, a service-master-key-protected database master key, non-empty core data, successful column decryption without displaying PII, `DBCC CHECKDB`, a valid transaction hash chain and reconciled account balances.

## 2. Point-in-time recovery drill

Run the following on the primary instance in this exact order:

1. `scenarios/01_pitr_capture_marker.sql` captures a pre-accident log backup, the expected recovery rows as JSON, and both UTC and SQL Server-local marker times.
2. Ask the lecturer to execute one or both controlled accidents individually:

   ```sql
   DELETE SmartBankDB.demo.RecoveryTarget WHERE RecoveryID = 1;
   DELETE SmartBankDB.demo.RecoveryTarget WHERE RecoveryID = 2;
   ```

3. `scenarios/02_pitr_capture_post_change_log.sql` refuses to continue unless the live rows differ from the marker and the accident is present in `audit.DmlAudit`. It then captures and verifies the closing encrypted log backup.
4. `operations/02_restore_point_in_time.sql` selects the eligible full backup, optional differential and ordered log chain from `msdb`, verifies every selected medium, and restores a separate `SmartBankDB_PITR` database using `STOPAT`.
5. `validation/02_validate_pitr_restore.sql` compares the restored rows and values exactly with the marker JSON, runs integrity checks and proves that the damaged live copy differs from the recovered copy.

The source database remains online throughout the restore because recovery targets a separate database. The scheduled five-minute transaction-log interval defines the normal-operation RPO; the explicit pre/post log backups make the classroom drill deterministic and do not replace the schedule.

## 3. Temporal row-recovery drill

Run `scenarios/03_temporal_row_recovery.sql` on the primary instance. It assigns one correlation ID, records the pre-change time, makes a controlled accidental change to customer `C00012`, retrieves the earlier row with `FOR SYSTEM_TIME AS OF`, and restores all customer columns. It contains a best-effort safety restoration if the temporal step fails.

Then run `validation/03_validate_temporal_recovery.sql`. It uses the correlation ID retained in DML audit rows to prove that:

- the accidental and restorative updates were both audited;
- the current row matches the pre-accident business values;
- the accidental version remains in temporal history; and
- no whole-database restore was required.

## 4. Cleanup

Cleanup is intentionally separate and confirmation-gated. Review the target names first, then run:

```powershell
sqlcmd -S "<instance>" -U sa -P "<sa-password>" -C -b -i "sql/recovery/utilities/01_cleanup_validation_databases.sql" -v ConfirmCleanup="DROP_RECOVERY_VALIDATION_DATABASES" PitrDatabaseName="SmartBankDB_PITR" RestoreValidationDatabaseName="SmartBankDB_RestoreDemo"
```

The utility rejects `SmartBankDB`, `SmartBankAnalyticsDB`, `master`, `model`, `msdb` and `tempdb`, and accepts only target names beginning with `SmartBankDB_`. It does not delete backup files, certificates, recovery markers or audit records.

## Acceptance summary

| Requirement evidence | Script |
|---|---|
| Encrypted full backup is genuinely restorable | `operations/01_restore_encrypted_full.sql` + `validation/01_validate_encrypted_full_restore.sql` |
| Broad accidental change is recoverable | PITR scenario + operation + validation |
| Recovery point can be selected within the log chain | `operations/02_restore_point_in_time.sql` |
| Small accidental row change is efficiently recoverable | Temporal scenario + validation |
| Recovery activity and manipulated rows are auditable | Scenario and validation queries against `audit.DmlAudit` |
| Recovery does not overwrite the active database | Both restore operations create explicitly named validation databases |
