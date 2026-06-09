# Module: `security-tooling` (geplant — noch nicht implementiert)

Org-weite **Detective Controls**: GuardDuty, Security Hub, IAM Access Analyzer,
zentral aggregiert.

## Core-Account
**Delegierter Administrator = Audit-Account** (NARA-Muster). Das Management-Account
delegiert die Security-Dienste an Audit, damit Findings nicht im Payer-Account
landen und das Security-Team eigenständig arbeitet.

## NARA-Ressourcen
- `aws_guardduty_organization_admin_account` + `aws_guardduty_organization_configuration`
  (`auto_enable_organization_members = "ALL"` → neue Accounts automatisch onboarded).
- `aws_securityhub_organization_admin_account` + `aws_securityhub_organization_configuration`
  + Standards (CIS, AWS Foundational).
- `aws_accessanalyzer_analyzer` (Typ `ORGANIZATION`).
- Delegation jeweils via `aws_organizations_delegated_administrator`.

## Cross-account-Beziehung
- **Management → Audit**: Delegation der Admin-Rolle für jeden Dienst.
- **Audit ← alle Accounts**: aggregiert Findings org-weit (auto-enable für neue
  Account-Factory-Accounts).
- **→ `log-archive`**: exportiert Findings/Events ins zentrale Log-Archive.
- Voraussetzung: Trusted Service Access in `organizations`
  (`guardduty/securityhub/access-analyzer.amazonaws.com` — bereits gesetzt).
