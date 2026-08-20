# Section 1 — Confidentiality demonstration

Run these files in numeric order. Use fresh SQL-authenticated connections for the named actors; changing database execution context is not authentication evidence.

| File | Assignment evidence | Run as |
|---|---|---|
| `01_all_users_authenticated.sql` | Server login, database user, business identity and role mapping | `sa`, then every demonstration login |
| `02_all_authenticated_users_staff_directory.sql` | Every authenticated user sees only staff name/contact directory fields | Every demonstration login |
| `03_bank_manager_visibility.sql` | Own record, officer records, all accounts and all transactions | Each manager |
| `04_bank_officer_visibility.sql` | Own record, all accounts and all transactions | Each officer |
| `05_dba_visibility.sql` | Own record only | DBA |
| `06_customer_visibility.sql` | Own profile, accounts and transactions only | Each customer |

The auditor login is an implementation extension. It still receives the common authenticated directory view, but it is not presented as one of the assignment's banking roles.
