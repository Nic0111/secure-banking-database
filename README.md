# SmartBank Database Security

This repository contains the complete Microsoft SQL Server implementation and report for the CT069-3-3 Database Security assignment. The design applies defence in depth across confidentiality, integrity, and availability rather than relying on one control.

## What is implemented

- SQL authentication with password policy, a distinct password per login, and separate database users
- Least-privilege RBAC for DBA, bank manager, bank officer, customer, and auditor roles
- Row-level security for staff employment data, customer records, accounts, and transactions
- Restricted views and stored procedures with no direct business-table DML for ordinary users
- AES-256 column-level encryption for national IDs, customer phones/addresses, and salaries
- Transparent Data Encryption (TDE) and AES-256 encrypted backups
- Salted SHA2-512 transaction-PIN hashing with retry lockout
- Dynamic data masking plus an automatically refreshed, irreversibly masked analytics database
- Temporal tables, constraints, atomic transaction processing, and a tamper-evident transaction hash chain
- SQL Server Audit for login/logout, DDL, permissions, and successful/failed data access
- Detailed DML audit records with before/after JSON for successful changes
- Automated full, differential, and five-minute transaction-log backups through SQL Server Agent
- Encrypted restore, point-in-time recovery, temporal recovery, and backup-health evidence scripts

## Requirements

- SQL Server 2022 or newer, Developer, Standard, or Enterprise Edition
- SQL Server Agent enabled and running
- SQLCMD (`sqlcmd`) for the automated deployment command
- Three server-side directories writable by the SQL Server service account (the deployment creates missing final directories when their parent exists):
  - backup directory
  - audit directory
  - certificate/key export directory (store this separately from backup media in a real deployment)

SQL Server Express is intentionally unsupported because it has no SQL Server Agent and cannot create encrypted backups.

## Repository layout

```text
sql/deploy.sql                 SQLCMD deployment orchestrator
sql/00-10_*.sql               Ordered implementation scripts
sql/tests/                     Role and security verification
sql/demo/                      Lecturer demonstration sequence
sql/recovery/                  Encrypted restore and point-in-time recovery
docs/                          Final report and supporting matrices
```

## Deployment

Run from the repository root. The coursework paths and demonstration credentials are declared at the top of `sql/deploy.sql`.

```bash
sqlcmd -S <server> -U sa -P '<sa-password>' -C -b -i sql/deploy.sql
```

For a different SQL Server instance, update the three directories and `PathSeparator` in `sql/deploy.sql`. Paths are resolved on the database server, not on the client Mac.

After deployment, run `sql/tests/00_admin_validation.sql`, then execute the remaining role scripts through fresh connections as described in `sql/tests/README.md`. Follow `sql/demo/README.md` for the lecturer sequence. Backup history needs at least three calendar days before the final demonstration.

## Security note

The supplied accounts, data, and credentials are fictitious and intended only for an isolated coursework environment. Do not reuse the committed demonstration passwords or keys. A production bank would additionally use managed secrets/HSM-backed keys, MFA at the identity tier, hardened TLS certificates, off-site immutable backup storage, high availability replicas, monitoring/SIEM, and formal key rotation.
