# SmartBank SSMS demonstration runbook

Use this file during the presentation. It tells you which SSMS connection and
which script to run. The SQL files show the evidence; this runbook explains the
order.

## Before the lecturer arrives

1. If you need a clean golden baseline, run `sql/deploy.sql` at least three
   completed backup days before the presentation. It resets the SmartBank
   databases and recreates the Agent jobs. Do not redeploy closer to the demo.
2. Confirm SQL Server Agent is running.
3. Open one SSMS window as `sa` and separate query windows for the demonstration
   logins you expect to use.
4. Run `00_preflight_and_baseline.sql` as `sa`.
5. For `02_integrity/05_customer_transactions.sql`, enable **Query > SQLCMD
   Mode** and add a temporary `:setvar DemoTransactionPin "..."` line locally.
   Do not save or show the PIN.

## 1. Authentication and role permissions

1. As `sa`, run `01_confidentiality/01_all_users_authenticated.sql` to show
   the eight logins, database users, identity mappings, and roles.
2. Open fresh SSMS connections as a manager, officer, customer, and DBA. Run
   the same script in each window to show `ORIGINAL_LOGIN()` and the assigned
   role.
3. At the SSMS login dialog, try one deliberately incorrect password. Do not
   display the password. Later, show its audit event with the auditor script.
4. As `sa`, run `99_consolidated_evidence.sql` if the lecturer wants the full
   permission matrix.

## 2. Confidentiality proof

Run the following in fresh connections. Each script first shows the permitted
result, then ends with an expected permission denial for a protected base table.

| Login | Script |
| --- | --- |
| Any non-customer SmartBank user | `01_confidentiality/02_all_authenticated_users_staff_directory.sql` |
| `sb_manager_daniel` or `sb_manager_siti` | `01_confidentiality/03_bank_manager_visibility.sql` |
| `sb_officer_farid` or `sb_officer_priya` | `01_confidentiality/04_bank_officer_visibility.sql` |
| `sb_dba_aisha` | `01_confidentiality/05_dba_visibility.sql` |
| `sb_customer_amelia` or `sb_customer_hafiz` | `01_confidentiality/06_customer_visibility.sql` |

The customer result is the automatic decryption evidence: the approved customer
procedure returns that customer's real profile values, while direct access to the
encrypted base table is denied.

## 3. Integrity and audit proof

Run these in order. Use the named login in the file header.

1. `02_integrity/01_dba_table_management_only.sql`
2. `02_integrity/02_manager_manages_staff.sql`
3. `02_integrity/03_officer_manages_customer_accounts.sql`
4. `02_integrity/04_staff_updates_own_record_except_salary.sql` as the
   officer `sb_officer_farid`. The same controlled procedure lets the DBA
   and managers update their own name/phone; salary remains protected
   and the DBA still has no direct DML on core.
5. `02_integrity/05_customer_transactions.sql` as `sb_customer_amelia`
6. `02_integrity/06_all_valid_invalid_manipulations_logged.sql` as
   `sb_auditor_noor`.

If asked to demonstrate permission changes, run
`90_permission_change_extension.sql` as `sa`. It creates and removes one
temporary contained user, membership, and permission, then shows the audit
metadata.

## 4. Three-day backup proof

As `sa`, run:

1. `03_availability/02_rpo_evidence.sql`
2. `03_availability/03_automated_backup_evidence.sql`

Show the daily backup summary for the three completed days before the demo,
then the enabled job schedules and successful job-history rows. The expected
intervals are full daily at 01:00, differential every six hours, and log every
five minutes.

## 5. Encrypted restore on a second SQL Server instance

Do this before the presentation on the second instance, then keep the restored
database online for inspection.

1. Copy the encrypted full backup and both certificate/key pairs to locations
   readable by the second SQL Server service account.
2. Open `recovery/operations/01_restore_encrypted_full.sql` in SSMS on that
   second instance.
3. Enable **Query > SQLCMD Mode** and set the variables shown in
   `recovery/README.md`. Use server-side Windows paths.
4. Run the restore, then run
   `recovery/validation/01_validate_encrypted_full_restore.sql` with the same
   `TargetDatabaseName` variable.

## 6. Point-in-time recovery during the presentation

On the primary instance as `sa`:

1. Run `recovery/scenarios/01_pitr_capture_marker.sql`.
2. Let the lecturer delete one or two rows from `demo.RecoveryTarget`.
3. Run `recovery/scenarios/02_pitr_capture_post_change_log.sql`.
4. Run `recovery/operations/02_restore_point_in_time.sql`.
5. Run `recovery/validation/02_validate_pitr_restore.sql`.
6. Return to `03_availability/01_accidental_changes_recoverable.sql` for the
   short side-by-side presentation of live and recovered rows.

The source database stays online. The restored copy is `SmartBankDB_PITR`.

## After the demonstration

Use `recovery/utilities/01_cleanup_validation_databases.sql` only if you need
to remove the two restore-validation databases. Redeploy only when you want a
new golden baseline.
