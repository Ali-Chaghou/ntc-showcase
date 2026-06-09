# Module: `guardrails` (geplant — noch nicht implementiert)

**Preventive + Detective Guardrails**: SCPs und Config Rules, an OUs gehängt.
(Basis-SCPs liegen bereits in `modules/organizations`; dieses Modul erweitert sie
zu einem vollständigen, OU-spezifischen Set.)

## Core-Account
SCP-Verwaltung im **Management-Account** (nur dort attachbar). Config Rules
org-weit über `security-tooling`/Audit ausgerollt.

## NARA-Ressourcen
- **Preventive (SCP)** `aws_organizations_policy` (Typ `SERVICE_CONTROL_POLICY`):
  - Region-Lock (Deny außerhalb erlaubter Regionen).
  - Deny Disable von CloudTrail/Config/GuardDuty (Schutz der Security-Baseline).
  - Deny Leave-Organization, Deny unverschlüsselte S3/EBS.
  - `aws_organizations_policy_attachment` differenziert pro OU
    (Sandbox lockerer, Prod strenger).
- **Detective** `aws_config_organization_managed_rule` (z.B. `S3_BUCKET_PUBLIC_READ_PROHIBITED`).

## Cross-account-Beziehung
- **Management → OUs/Accounts**: SCPs wirken vererbend auf alle (auch neue) Accounts der OU.
- **← `organizations`**: konsumiert `ou_ids` als `target_id`.
- **→ `log-archive`**: Config-Rule-Auswertungen fließen ins zentrale Archiv.
- Differenzierung je OU = unterschiedlicher Risk-Appetit pro Umgebung.
