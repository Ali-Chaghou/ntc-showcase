# Module: `identity-center` (geplant — noch nicht implementiert)

Zentrales **AWS IAM Identity Center (SSO)**: Permission Sets + Zuweisungen an
Accounts/OUs.

## Core-Account
Läuft im **Management-Account** (oder einem delegierten Admin-Account). Identity
Center ist ein org-weiter Dienst und kann nur einmal pro Org/Region aktiviert
werden.

## NARA-Ressourcen
- `data.aws_ssoadmin_instances` (Instanz wird nicht von TF erstellt, nur referenziert).
- `aws_ssoadmin_permission_set` je Rolle (Admin/PowerUser/ReadOnly/SecurityAudit)
  mit `session_duration` + `relay_state`.
- `aws_ssoadmin_managed_policy_attachment` / `aws_ssoadmin_permission_set_inline_policy`.
- `aws_identitystore_group` + `aws_ssoadmin_account_assignment`
  (Group × PermissionSet × Account).

## Cross-account-Beziehung
- Weist Permission Sets **an alle Workload-Accounts** zu (aus `account-factory`
  `workload_account_ids` + Security-Accounts).
- Ersetzt statische IAM-User → kurzlebige Rollen-Sessions in jedem Account.
- Verknüpft mit `guardrails`: SCP `RequireMFAForConsole` greift, MFA wird am
  IdP/Identity-Center erzwungen.
