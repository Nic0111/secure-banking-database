USE [$(DatabaseName)];
GO
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'sec.fn_StaffEmploymentAccess', N'IF') IS NULL
BEGIN
    EXEC(N'
    CREATE FUNCTION sec.fn_StaffEmploymentAccess
    (
        @StaffID char(6),
        @Position varchar(20)
    )
    RETURNS TABLE
    WITH SCHEMABINDING
    AS
    RETURN
    (
        SELECT 1 AS IsAllowed
        WHERE USER_NAME() = N''dbo''
           OR EXISTS
           (
               SELECT 1
               FROM sec.PrincipalMap AS principalMap
               WHERE principalMap.LoginName = ORIGINAL_LOGIN()
                 AND principalMap.IsActive = 1
                 AND (principalMap.EffectiveTo IS NULL OR principalMap.EffectiveTo > SYSUTCDATETIME())
                 AND
                 (
                     principalMap.StaffID = @StaffID
                     OR (principalMap.UserType = ''MANAGER'' AND @Position = ''BANK_OFFICER'')
                 )
           )
    );');
END;
GO

IF OBJECT_ID(N'sec.fn_CustomerAccess', N'IF') IS NULL
BEGIN
    EXEC(N'
    CREATE FUNCTION sec.fn_CustomerAccess
    (
        @CustomerID char(6)
    )
    RETURNS TABLE
    WITH SCHEMABINDING
    AS
    RETURN
    (
        SELECT 1 AS IsAllowed
        WHERE USER_NAME() = N''dbo''
           OR EXISTS
           (
               SELECT 1
               FROM sec.PrincipalMap AS principalMap
               WHERE principalMap.LoginName = ORIGINAL_LOGIN()
                 AND principalMap.IsActive = 1
                 AND (principalMap.EffectiveTo IS NULL OR principalMap.EffectiveTo > SYSUTCDATETIME())
                 AND
                 (
                     principalMap.UserType IN (''MANAGER'', ''OFFICER'')
                     OR principalMap.CustomerID = @CustomerID
                 )
           )
    );');
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = N'StaffEmploymentSecurityPolicy')
BEGIN
    CREATE SECURITY POLICY sec.StaffEmploymentSecurityPolicy
        ADD FILTER PREDICATE sec.fn_StaffEmploymentAccess(StaffID, Position)
            ON core.StaffEmployment
        WITH (STATE = ON, SCHEMABINDING = ON);
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.security_policies WHERE name = N'CustomerDataSecurityPolicy')
BEGIN
    CREATE SECURITY POLICY sec.CustomerDataSecurityPolicy
        ADD FILTER PREDICATE sec.fn_CustomerAccess(CustomerID)
            ON core.Customer,
        ADD FILTER PREDICATE sec.fn_CustomerAccess(CustomerID)
            ON core.Account,
        ADD FILTER PREDICATE sec.fn_CustomerAccess(CustomerID)
            ON core.TransactionRecord
        WITH (STATE = ON, SCHEMABINDING = ON);
END;
GO
