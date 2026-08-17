# Section 3 — Availability demonstration

The files here present evidence; they do not duplicate operational restore logic. Actual restore commands stay in `sql/recovery` because they create validation databases and require a controlled administrator workflow.

| File | Assignment evidence | Run as |
|---|---|---|
| `01_accidental_changes_recoverable.sql` | Recovery marker, deletion audit and restored point-in-time rows | `sa` |
| `02_rpo_evidence.sql` | Five-minute log-backup schedule and measured latest-backup age | `sa` |
| `03_automated_backup_evidence.sql` | Enabled full, differential and log jobs plus encrypted, checked and verified backup history | `sa` |

For point-in-time recovery, execute the current recovery workflow in order: `sql/recovery/02_capture_pitr_marker.sql`, make the accidental change, `03_capture_post_change_log.sql`, and `04_restore_point_in_time.sql`. Then return here and rerun `01_accidental_changes_recoverable.sql` for the comparison result. Row-level temporal recovery is implemented in `sql/recovery/05_temporal_row_recovery.sql`.
