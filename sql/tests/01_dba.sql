-- Connect as: sb_dba_aisha
USE [SmartBankDB];
GO

SELECT * FROM api.vw_StaffDirectory;            -- SUCCESS: every authenticated user sees staff name and phone.
EXEC api.usp_GetMyStaffProfile;                 -- SUCCESS: exactly the DBA's own decrypted record.

-- EXPECTED DENIAL: DBA cannot read the business base table.
SELECT * FROM core.Staff;
GO

-- SUCCESS: DBA can create and manage table definitions.
IF OBJECT_ID(N'core.DbaValidationProof', N'U') IS NOT NULL
    DROP TABLE core.DbaValidationProof;
CREATE TABLE core.DbaValidationProof (ProofID int NOT NULL CONSTRAINT PK_DbaValidationProof PRIMARY KEY);
GO

-- SUCCESS: ALTER is independently allowed and audited.
ALTER TABLE core.DbaValidationProof ADD ProofNote nvarchar(100) NULL;
GO

-- EXPECTED DENIAL: even on the new table, the DBA role cannot manipulate data.
INSERT core.DbaValidationProof (ProofID, ProofNote) VALUES (1, N'DBA must not insert this row');
GO

-- SUCCESS: DDL management is allowed and audited.
DROP TABLE core.DbaValidationProof;
GO

-- EXPECTED DENIAL: DBA is not a manager.
EXEC api.usp_ManagerGetStaffProfiles;
GO
