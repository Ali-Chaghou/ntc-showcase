# Module: `parameters` (geplant — noch nicht implementiert)

Verteilt **gemeinsame Landing-Zone-Werte** (Account-IDs, TGW-ID, OU-ARNs,
CIDR-Ranges) als SSM-Parameter in jeden Account — das „Service-Discovery“ der
Landing Zone.

## Core-Account
Schreibt zentral (z.B. Management/Network-Account) und verteilt cross-account in
alle Workload-Accounts, damit lokale Stacks die Werte ohne Remote-State-Zugriff
lesen können.

## NARA-Ressourcen
- `aws_ssm_parameter` je Wert (z.B. `/ntc/network/transit-gateway-id`,
  `/ntc/org/workloads-ou-arn`, `/ntc/log-archive/bucket-arn`).
- Optional cross-account-Verteilung via `aws_ssm_parameter` im Ziel-Account
  (assume-role) ODER zentral + RAM/Resolver-Pattern.
- Konsistentes Namensschema `/ntc/<domain>/<key>` analog Ressourcen-Naming.

## Cross-account-Beziehung
- **← alle Module**: konsumiert Outputs (`transit_gateway_id` aus `core-network`,
  `ou_ids` aus `organizations`, `bucket_arn` aus `log-archive`, …).
- **→ Workload-Stacks**: Apps/Module lesen Parameter per `data.aws_ssm_parameter`
  statt harte Kopplung an Remote-State — entkoppelt Deploy-Reihenfolge.
- Neue Account-Factory-Accounts holen sich die Baseline-Werte automatisch.
