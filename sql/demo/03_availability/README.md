# Section 3 — Availability demonstration

The files here present concise demonstration evidence; they do not duplicate the operational restore logic. Actual recovery scenarios, restore commands, and detailed validation remain in `sql/recovery` because they create or modify validation databases and require a controlled administrator workflow.

| File | Assignment evidence | Run as |
|---|---|---|
| `01_accidental_changes_recoverable.sql` | Recovery marker, deletion audit and restored point-in-time rows | `sa` |
| `02_rpo_evidence.sql` | Five-minute log-backup schedule and measured latest-backup age | `sa` |
| `03_automated_backup_evidence.sql` | Enabled full, differential and log jobs plus encrypted, checked and verified backup history | `sa` |

Before presenting the availability evidence, complete the applicable workflow from `sql/recovery/README.md`:

1. **Encrypted full restore:** run `sql/recovery/operations/01_restore_encrypted_full.sql`, followed by `sql/recovery/validation/01_validate_encrypted_full_restore.sql`.
2. **Point-in-time recovery:** run `sql/recovery/scenarios/01_pitr_capture_marker.sql`, perform the demonstrated accidental deletion, run `sql/recovery/scenarios/02_pitr_capture_post_change_log.sql`, then run `sql/recovery/operations/02_restore_point_in_time.sql` and `sql/recovery/validation/02_validate_pitr_restore.sql`.
3. **Temporal row recovery:** run `sql/recovery/scenarios/03_temporal_row_recovery.sql`, followed by `sql/recovery/validation/03_validate_temporal_recovery.sql`.

After the point-in-time workflow succeeds, return here and run `01_accidental_changes_recoverable.sql` to present the condensed live-versus-recovered comparison during the assignment demonstration.
