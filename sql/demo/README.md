# SmartBank assignment demonstration

This folder is the presentation layer for the implemented SmartBank security controls. It does not replace the automated assertions in `sql/tests`. Follow [SSMS_RUNBOOK.md](SSMS_RUNBOOK.md) for presentation order: use SSMS dialogs for administration and restores, and query windows for application operations and validation. Script numbering groups assignment evidence; it is not the complete execution sequence.

## Before the demonstration

1. Follow `SSMS_RUNBOOK.md`. It is the single presentation checklist.
2. Start from the golden baseline, then run `00_preflight_and_baseline.sql` as `sa`.
3. Open a fresh SSMS connection for every named login. Do not use `EXECUTE AS` as evidence of server authentication.
4. SQLCMD mode is needed for the customer-transaction script and the recovery scripts that use SQLCMD variables. Never place a password or PIN in a screenshot or source file.
5. Keep the `sa` and `sb_auditor_noor` connections available for the audit and availability evidence.

Expected permission and business-rule errors are part of the evidence. Read the short comment immediately before each expected error, then continue to the next section. Login failures must be demonstrated at the SSMS connection dialog and then viewed in SQL Server Audit.

## Recommended run order

| Order | Script or folder | Connection | Data effect |
|---:|---|---|---|
| 1 | `00_preflight_and_baseline.sql` | `sa` | Read-only |
| 2 | `01_confidentiality` in numeric order | The login named in each header | Read-only |
| 3 | Integrity `01`, `02`, new-login dialog plus remaining `07` mapping, then `03`–`05` | The login named in the runbook | Controlled demo changes |
| 4 | Optional `90_permission_change_extension.sql`, then integrity `06` once | `sa`, then `sb_auditor_noor` | Reversible permission example, followed by audit evidence |
| 5 | Backup-job dialogs, then availability `02` and `03` | `sa` on primary | Read-only evidence |
| 6 | Encrypted restore/validation on second instance; PITR dialog/validation on primary; optional one-file in-place tail-log recovery on primary; temporal scenario/validation | `sa` on the specified instance | Follow the exact GUI and query steps in `SSMS_RUNBOOK.md` |
| 7 | `99_consolidated_evidence.sql` | `sa` | Read-only |

After a full demonstration, restore the golden baseline before repeating it. This removes the deliberately opened test account and the appended transaction evidence while retaining a predictable starting state.

## Evidence rules

- Capture the query text, connected login, result grid, and timestamp together where practical.
- A successful restricted query is not a pass unless the visible rows match the assignment boundary.
- A denial is not a pass unless the corresponding permitted operation is also shown.
- Do not expose encrypted source values, login passwords, transaction PINs, certificate private keys, or full audit statements containing secrets.
- The security auditor is an additional separation-of-duties control, not a substitute for any assignment actor.

## Demo boundary

The DBA demonstration on base tables is limited to table definitions. The DBA
may update only its own name/phone through the controlled own-profile script;
salary remains protected and no base-table DML is possible. Managers and
officers use the same script for the staff-contact requirement.
