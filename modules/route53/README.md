# Module: `route53` (geplant — noch nicht implementiert)

Zentrales **DNS**: private Hosted Zones + zentrale Resolver-Endpoints für
hybride/cross-account-Namensauflösung.

## Core-Account
**Network-/Connectivity-Account** (DNS gehört zum Hub). Resolver-Endpoints
liegen in der Hub-VPC und sind über den TGW erreichbar.

## NARA-Ressourcen
- `aws_route53_zone` (private) je Domain, initial mit der Hub-VPC verknüpft.
- `aws_route53_vpc_association_authorization` (im Zone-Owner-Account) +
  `aws_route53_zone_association` (im Workload-Account) → **cross-account**
  Verknüpfung weiterer VPCs an dieselbe Zone.
- `aws_route53_resolver_endpoint` (inbound/outbound) + `aws_route53_resolver_rule`
  + `aws_route53_resolver_rule_association` für Forwarding nach on-prem.
- RAM-Share der Resolver Rules an die Workloads-OU.

## Cross-account-Beziehung
- **← `vpc`**: konsumiert `vpc_ids` der Workload-VPCs für die Zone-Association.
- **← `core-network`**: DNS-Queries laufen über den TGW (`dns_support = enable`)
  zwischen Spokes und Hub-Resolver.
- **→ on-prem**: Resolver Rules forwarden Firmen-Domains über VPN/DX.
