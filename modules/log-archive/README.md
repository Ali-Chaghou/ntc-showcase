# Module: `log-archive` (geplant — noch nicht implementiert)

Zentrales, unveränderliches **Log-Archiv** für org-weites CloudTrail + Config.

## Core-Account
**Log-Archive-Account** (eigenes Account in der Security-OU). Bewusst getrennt
vom Audit-Account: Audit *liest/analysiert*, Log-Archive *speichert
write-once* — Separation of Duties.

## NARA-Ressourcen
- `aws_cloudtrail` als **Organization Trail** (`is_organization_trail = true`),
  erstellt im Management-Account, Ziel-Bucket im Log-Archive.
- `aws_s3_bucket` mit Object Lock (WORM), Versioning, SSE-KMS, `aws_s3_bucket_policy`
  die nur den Org-Principal schreiben lässt (`aws:PrincipalOrgID`).
- `aws_config_configuration_aggregator` (org-weit) + Delivery Channel in den Bucket.
- Lifecycle-Rules: Übergang nach Glacier, Retention nach Compliance-Vorgabe.

## Cross-account-Beziehung
- **Alle Accounts → Log-Archive**: schreiben CloudTrail/Config in den zentralen
  Bucket (Bucket-Policy via `aws:PrincipalOrgID`, kein Per-Account-Grant nötig).
- **Audit (`security-tooling`) → Log-Archive**: Findings/Events-Export.
- Org-Trail deckt automatisch neue Account-Factory-Accounts ab (kein Re-Config).
