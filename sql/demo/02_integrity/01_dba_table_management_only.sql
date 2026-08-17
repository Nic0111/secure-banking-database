/*
ASSIGNMENT SECTION:
Section 2 - Integrity

REQUIREMENT:
1. Only the DBA may manage table definitions; the DBA must not manipulate banking
business data.

RUN AS:
sb_dba_aisha in a fresh SQL-authenticated connection.

EXPECTED RESULT:
The DBA creates, alters and drops core.DemoDbaDdlProof. An INSERT into that table
is denied by the schema-level DML restriction.

PASS CONDITION:
All three DDL operations succeed, the DML attempt fails, and the temporary proof
table is removed at the end.

DATABASE CHANGES:
Creates, alters and drops core.DemoDbaDdlProof. DDL audit evidence remains.
*/
USE [SmartBankDB];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF ORIGINAL_LOGIN() <> N'sb_dba_aisha' OR IS_ROLEMEMBER(N'rl_dba') <> 1
    THROW 51200, 'Run this script as sb_dba_aisha.', 1;

IF OBJECT_ID(N'core.DemoDbaDdlProof', N'U') IS NOT NULL
    DROP TABLE core.DemoDbaDdlProof;

CREATE TABLE core.DemoDbaDdlProof
(
    ProofID int NOT NULL CONSTRAINT PK_DemoDbaDdlProof PRIMARY KEY,
    ProofText nvarchar(100) NULL
);

ALTER TABLE core.DemoDbaDdlProof
    ADD CreatedAt datetime2(3) NOT NULL
        CONSTRAINT DF_DemoDbaDdlProof_CreatedAt DEFAULT (SYSUTCDATETIME());

SELECT OBJECT_SCHEMA_NAME(columnInfo.object_id) AS SchemaName,
       OBJECT_NAME(columnInfo.object_id) AS TableName,
       columnInfo.column_id,
       columnInfo.name AS ColumnName,
       TYPE_NAME(columnInfo.user_type_id) AS DataType
FROM sys.columns AS columnInfo
WHERE columnInfo.object_id = OBJECT_ID(N'core.DemoDbaDdlProof')
ORDER BY columnInfo.column_id;

DECLARE @DmlWasDenied bit = 0;
DECLARE @DenialNumber int = NULL;
DECLARE @DenialMessage nvarchar(4000) = NULL;
BEGIN TRY
    EXEC sys.sp_executesql
        N'INSERT core.DemoDbaDdlProof (ProofID, ProofText) VALUES (1, N''must be denied'');';
END TRY
BEGIN CATCH
    SELECT @DmlWasDenied = 1, @DenialNumber = ERROR_NUMBER(), @DenialMessage = ERROR_MESSAGE();
END CATCH;

DROP TABLE core.DemoDbaDdlProof;

IF @DmlWasDenied = 0
    THROW 51201, 'FAIL - DBA DML unexpectedly succeeded.', 1;
IF OBJECT_ID(N'core.DemoDbaDdlProof', N'U') IS NOT NULL
    THROW 51202, 'FAIL - temporary DDL proof table was not removed.', 1;

SELECT N'PASS' AS Result,
       N'DBA completed table DDL but business-data manipulation was denied.' AS Evidence,
       @DenialNumber AS ExpectedDenialNumber,
       @DenialMessage AS ExpectedDenialMessage;
GO
