# Section 2 — Integrity demonstration

These scripts pair an allowed operation with a prohibited or invalid operation, then use the audit script to show both outcomes. Run each business operation using the real login named in its header.

| File | Assignment evidence | Run as |
| --- | --- | --- |
| `01_dba_table_management_only.sql` | DBA manages table definitions but not business rows | DBA |
| `02_manager_manages_staff.sql` | Manager updates own-branch officer and DBA records, hires a new officer into own branch; cross-branch and non-eligible targets are rejected | `sb_manager_daniel` |
| `03_officer_manages_customer_accounts.sql` | Officer opens and controls customer accounts | Officer |
| `04_staff_updates_own_record_except_salary.sql` | Staff member (officer shown) updates own name/phone; salary remains protected | Officer (DBA and managers use the same procedure) |
| `05_customer_transactions.sql` | Customer performs valid transactions; invalid requests are rejected | Customer |
| `07_sa_wires_new_officer_login.sql` | Server administrator (sa) creates the SQL login and database-side wiring for the officer the manager hired; the DBA cannot do this | `sa` |
| `06_all_valid_invalid_manipulations_logged.sql` | Successful and failed attempts are traceable | Security auditor |

The account-opening and transaction scripts intentionally append evidence. Restore the golden baseline before repeating the full demonstration. The DBA is limited to table definitions on base tables; it may change only its own name/phone through the controlled procedure, and salary remains protected.
