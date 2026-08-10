# Restore and recovery runbook

## A. Encrypted backup on another SQL instance

1. Copy the latest full `.bak` to a directory readable by the second instance.
2. Copy both certificate/private-key pairs from the protected key directory to the second instance:
   - `SmartBank_TDE_Certificate.cer` and `.pvk`
   - `SmartBank_Backup_Certificate.cer` and `.pvk`
3. Keep certificate/key media separate from database backup media outside this coursework environment.
4. Run `01_restore_encrypted_full.sql` on the second instance with mandatory SQLCMD variables for its target name, file paths and key passwords:

   ```bash
   sqlcmd -S <second-server> -U sa -P '<sa-password>' -C -b \
     -i sql/recovery/01_restore_encrypted_full.sql \
     -v TargetDatabaseName='SmartBankDB_RestoreDemo' \
        SourceFullBackupFile='<server-side-full-backup-path>' \
        TargetDataFile='<server-side-target-mdf-path>' \
        TargetLogFile='<server-side-target-ldf-path>' \
        TargetCertificateDirectory='<server-side-certificate-path>' \
        PathSeparator='\' \
        TargetMasterKeyPassword='<new-target-master-key-password>' \
        CertificateBackupPassword='<certificate-export-password>' \
        RestoredDatabaseMasterKeyPassword='<source-database-master-key-password>'
   ```

5. Show `RESTORE VERIFYONLY`, restored row counts, TDE status, ledger verification, and decrypted customer PII.

The backup cannot be restored without both private certificates. TDE protects the database pages/backups, while explicit backup encryption independently protects the backup media.

## B. Point-in-time recovery drill

1. As `sa`, run `02_capture_pitr_marker.sql`. It records both UTC evidence time and SQL Server-local `STOPAT` time; save both values.
2. Ask the lecturer to run one or both statements individually:

   ```sql
   DELETE SmartBankDB.demo.RecoveryTarget WHERE RecoveryID = 1;
   DELETE SmartBankDB.demo.RecoveryTarget WHERE RecoveryID = 2;
   ```

3. Show the rows are missing and that `audit.DmlAudit` captured the deletion.
4. Immediately run `03_capture_post_change_log.sql`. This encrypted log backup closes the recovery chain around the deletion.
5. Run `04_restore_point_in_time.sql` on the primary instance. It automatically selects the correct full, optional differential, and ordered log chain from `msdb`, then restores `SmartBankDB_PITR` with `STOPAT` equal to the marker.
6. Query `SmartBankDB_PITR.demo.RecoveryTarget`; the deleted rows are present in the recovered copy while the active source database remains online.

The five-minute scheduled log interval defines a five-minute RPO under ordinary operation. The on-demand post-change log capture is a recovery operation, not a substitute for scheduled backups.

## C. Fast row recovery with temporal history

Run `05_temporal_row_recovery.sql` to demonstrate efficient recovery of an accidental customer update without restoring the whole database. Backups remain necessary for database/media failure and arbitrary point-in-time recovery.
