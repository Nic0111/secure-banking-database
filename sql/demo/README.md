# Lecturer demonstration runbook

Open one SSMS/Azure Data Studio connection per login. Execute each statement individually so the result and corresponding audit event are easy to explain.

1. As `sa`, run `01_security_inventory.sql` to show all users, roles, explicit grants/denies, RLS predicates, DDM rules, encryption status, and job schedules.
2. Connect as the DBA, both managers, both officers, and both customers. Use the matching scripts in `../tests/` to prove each allowed action, denial, validation failure, and peer-manager isolation boundary.
3. Attempt one invalid password login and retain the error. SQL Server Audit records it through `FAILED_LOGIN_GROUP`.
4. Run `02_audit_evidence.sql` as `sa` or the auditor to correlate login/logout, DML, DDL, procedure, and permission events.
5. Run `03_backup_evidence.sql` after at least three consecutive days. It proves full/differential/log frequency, AES-256 encryption, checksums, verification, and job success.
6. On the second instance, run `../recovery/01_restore_encrypted_full.sql`, then show row counts and automatic customer PII decryption.
7. For point-in-time recovery, follow `../recovery/README.md`: capture a marker, let the lecturer delete one or two `demo.RecoveryTarget` rows, capture a post-change log backup, and restore to `SmartBankDB_PITR` at the marker.
8. If asked to add a user/change permissions, run `04_permission_change.sql`, then rerun audit evidence and point to the database role/permission audit event.
9. Run `05_consolidated_evidence.sql` at any point for a concise live snapshot of server state, dataset size, role membership, RLS, masking, audit totals, backup history, jobs, and recovery copies.

Do not expose key passwords on screen. Certificate files and their private-key password are required for a cross-instance encrypted restore.
