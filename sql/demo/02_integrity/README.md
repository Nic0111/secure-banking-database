# Section 2 — Integrity demonstration

These scripts pair an allowed operation with a prohibited or invalid operation, then use the audit script to show both outcomes. Run each business operation using the real login named in its header.

| File | Assignment evidence | Run as |
| --- | --- | --- |
| `01_dba_table_management_only.sql` | DBA manages table definitions but not business rows | DBA |
| `02_manager_manages_staff.sql` | Manager updates officer and DBA records; non-eligible targets are rejected | Manager |
| `03_officer_manages_customer_accounts.sql` | Officer opens and controls customer accounts | Officer |
| `04_staff_updates_own_record_except_salary.sql` | Officer updates own name/phone; salary remains protected | Officer |
| `05_customer_transactions.sql` | Customer performs valid transactions; invalid requests are rejected | Customer |
| `06_all_valid_invalid_manipulations_logged.sql` | Successful and failed attempts are traceable | Security auditor |

The account-opening and transaction scripts intentionally append evidence. Restore the golden baseline before repeating the full demonstration. The DBA is limited to table definitions and does not change business data.
