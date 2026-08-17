/*
ASSIGNMENT SECTION:
Section 2 - Integrity

REQUIREMENT:
3. Bank Officers may manage customer accounts.

RUN AS:
sb_officer_farid or sb_officer_priya in a fresh connection, after restoring the
golden baseline.

EXPECTED RESULT:
The officer opens ATEST00001 for customer C00012, freezes it and restores it to
ACTIVE. An invalid account type and a direct balance update are rejected.

PASS CONDITION:
The controlled account operations succeed, both invalid/direct operations fail,
and the new account has zero balance and ACTIVE status.

DATABASE CHANGES:
Creates ATEST00001 and retains it as audit/demo evidence. Restore the golden
baseline before repeating the full demonstration.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF IS_ROLEMEMBER(N'rl_officer') <> 1
    THROW 51220, 'Run this script as a bank-officer login.', 1;
IF EXISTS (SELECT 1 FROM api.vw_CustomerAccountSummary WHERE AccountID = 'ATEST00001')
    THROW 51221, 'ATEST00001 already exists. Restore the golden baseline before rerunning this demo.', 1;

EXEC api.usp_OfficerOpenAccount
     @AccountID = 'ATEST00001', @CustomerID = 'C00012', @AccountType = 'SAVINGS';
EXEC api.usp_OfficerSetAccountStatus @AccountID = 'ATEST00001', @Status = 'FROZEN';

SELECT N'Controlled officer freeze' AS Evidence, *
FROM api.vw_CustomerAccountSummary WHERE AccountID = 'ATEST00001';
IF NOT EXISTS
   (
       SELECT 1 FROM api.vw_CustomerAccountSummary
       WHERE AccountID = 'ATEST00001' AND CustomerID = 'C00012'
         AND AccountType = 'SAVINGS' AND Balance = 0 AND Status = 'FROZEN'
   )
    THROW 51222, 'FAIL - officer account creation/freeze did not produce the expected state.', 1;

EXEC api.usp_OfficerSetAccountStatus @AccountID = 'ATEST00001', @Status = 'ACTIVE';

DECLARE @Rejected table (Attempt nvarchar(120), ErrorNumber int, ErrorMessage nvarchar(4000));
BEGIN TRY
    EXEC api.usp_OfficerOpenAccount
         @AccountID = 'ABAD000001', @CustomerID = 'C00012', @AccountType = 'CRYPTO';
    THROW 51223, 'FAIL - invalid account type unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51223 THROW;
    INSERT @Rejected VALUES (N'Open account with invalid account type', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

BEGIN TRY
    EXEC sys.sp_executesql N'UPDATE core.Account SET Balance = 999999 WHERE AccountID = ''ATEST00001'';';
    THROW 51224, 'FAIL - officer direct balance update unexpectedly succeeded.', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51224 THROW;
    INSERT @Rejected VALUES (N'Direct account-balance update', ERROR_NUMBER(), ERROR_MESSAGE());
END CATCH;

SELECT N'Final controlled account state' AS Evidence, *
FROM api.vw_CustomerAccountSummary WHERE AccountID = 'ATEST00001';
SELECT N'PASS' AS Result, Attempt, ErrorNumber, ErrorMessage AS ExpectedRejection
FROM @Rejected ORDER BY Attempt;

IF (SELECT COUNT(*) FROM @Rejected) <> 2
   OR NOT EXISTS
      (
          SELECT 1 FROM api.vw_CustomerAccountSummary
          WHERE AccountID = 'ATEST00001' AND Balance = 0 AND Status = 'ACTIVE'
      )
    THROW 51225, 'FAIL - officer account-management controls did not finish in the expected state.', 1;
GO
