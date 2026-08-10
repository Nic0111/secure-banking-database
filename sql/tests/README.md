# Security validation

Run each role script in a fresh connection using the login named at the top of the file. This is important: `EXECUTE AS USER` is not an adequate substitute for testing SQL authentication, native login audit, dynamic masking, or `ORIGINAL_LOGIN()`-based identity mapping.

Recommended order:

1. `00_admin_validation.sql` as `sa`
2. `01_dba.sql` as `sb_dba_aisha`
3. `02_manager.sql` as `sb_manager_daniel`
4. `03_officer.sql` as `sb_officer_farid`
5. `04_customer_amelia.sql` as `sb_customer_amelia`
6. `05_customer_hafiz.sql` as `sb_customer_hafiz`
7. `06_auditor.sql` as `sb_auditor_noor`
8. `07_post_test_audit.sql` as `sa` or the auditor

Statements labelled **EXPECTED DENIAL** must fail. A denial is a passing security result, not a test failure. Execute statements individually during the lecturer demonstration so each permission boundary is visible and independently audited.

