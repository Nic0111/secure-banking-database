# Security validation

Run each role script in a fresh connection using the login named at the top of the file. This is important: `EXECUTE AS USER` is not an adequate substitute for testing SQL authentication, native login audit, dynamic masking, or `ORIGINAL_LOGIN()`-based identity mapping.

Recommended order:

1. `00_admin_validation.sql` as `sa`
2. `01_dba.sql` as `sb_dba_aisha`
3. `02_manager.sql` as `sb_manager_daniel`
4. `02_manager.sql` again as `sb_manager_siti`
5. `03_officer.sql` as `sb_officer_farid`
6. `03_officer.sql` again as `sb_officer_priya`
7. `04_customer_amelia.sql` as `sb_customer_amelia`
8. `05_customer_hafiz.sql` as `sb_customer_hafiz`
9. `06_auditor.sql` as `sb_auditor_noor`
10. `07_post_test_audit.sql` as `sa` or the auditor

Every SQL login has a distinct demonstration password. The login-to-variable mapping is declared at the top of `sql/deploy.sql`; do not substitute one officer's or customer's password for another login.

Statements labelled **EXPECTED DENIAL** or **EXPECTED VALIDATION FAILURE** must fail. These failures are passing security results, not test failures. Execute statements individually during the lecturer demonstration so each permission boundary is visible and independently audited.
