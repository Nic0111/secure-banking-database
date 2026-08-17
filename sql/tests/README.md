```bash
set -u

: "${SB_SERVER:?Set SB_SERVER to the SQL Server instance before running the suite}"

test_failures=0

run_test() {
  echo "\n===== $3 as $1 ====="
  if ! sqlcmd -S "$SB_SERVER" -U "$1" -P "$2" -C -b -V 16 -i "$3"; then
    echo "FAIL: $3 as $1"
    test_failures=$((test_failures + 1))
  fi
}

# Baseline and confidentiality
run_test sa 'user@123' sql/tests/00_admin_validation.sql
run_test sa 'user@123' sql/tests/01_confidentiality/01_authentication_assertions.sql
run_test sb_customer_amelia 'SBank!Customer_2026#Amelia' sql/tests/01_confidentiality/02_staff_directory_assertions.sql
run_test sb_manager_daniel 'SBank!Manager_2026#Daniel' sql/tests/01_confidentiality/03_manager_access_assertions.sql
run_test sb_manager_siti 'SBank!Manager_2026#Siti' sql/tests/01_confidentiality/03_manager_access_assertions.sql
run_test sb_officer_farid 'SBank!Officer_2026#Farid' sql/tests/01_confidentiality/04_officer_access_assertions.sql
run_test sb_officer_priya 'SBank!Officer_2026#Priya' sql/tests/01_confidentiality/04_officer_access_assertions.sql
run_test sb_dba_aisha 'SBank!Dba_2026#Aisha' sql/tests/01_confidentiality/05_dba_access_assertions.sql
run_test sb_customer_amelia 'SBank!Customer_2026#Amelia' sql/tests/01_confidentiality/06_customer_isolation_assertions.sql
run_test sb_customer_hafiz 'SBank!Customer_2026#Hafiz' sql/tests/01_confidentiality/06_customer_isolation_assertions.sql

# Integrity
run_test sb_dba_aisha 'SBank!Dba_2026#Aisha' sql/tests/02_integrity/01_dba_ddl_assertions.sql
run_test sb_manager_daniel 'SBank!Manager_2026#Daniel' sql/tests/02_integrity/02_manager_staff_assertions.sql
run_test sb_manager_siti 'SBank!Manager_2026#Siti' sql/tests/02_integrity/02_manager_staff_assertions.sql
run_test sb_officer_farid 'SBank!Officer_2026#Farid' sql/tests/02_integrity/03_officer_account_assertions.sql
run_test sb_officer_priya 'SBank!Officer_2026#Priya' sql/tests/02_integrity/03_officer_account_assertions.sql
run_test sb_manager_daniel 'SBank!Manager_2026#Daniel' sql/tests/02_integrity/04_own_record_assertions.sql
run_test sb_manager_siti 'SBank!Manager_2026#Siti' sql/tests/02_integrity/04_own_record_assertions.sql
run_test sb_officer_farid 'SBank!Officer_2026#Farid' sql/tests/02_integrity/04_own_record_assertions.sql
run_test sb_officer_priya 'SBank!Officer_2026#Priya' sql/tests/02_integrity/04_own_record_assertions.sql
run_test sb_customer_amelia 'SBank!Customer_2026#Amelia' sql/tests/02_integrity/05_transaction_assertions.sql
run_test sb_customer_hafiz 'SBank!Customer_2026#Hafiz' sql/tests/02_integrity/05_transaction_assertions.sql
run_test sb_auditor_noor 'SBank!Auditor_2026#Noor' sql/tests/02_integrity/06_audit_assertions.sql

# Availability
run_test sa 'user@123' sql/tests/03_availability/01_backup_assertions.sql
run_test sa 'user@123' sql/tests/03_availability/02_rpo_assertions.sql
run_test sa 'user@123' sql/tests/03_availability/03_recovery_assertions.sql

if ((test_failures > 0)); then
  echo "TEST SUITE FAILED: $test_failures invocation(s) failed."
  exit 1
fi

echo "TEST SUITE PASSED."
```
