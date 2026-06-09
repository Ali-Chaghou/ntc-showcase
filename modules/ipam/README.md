# Module: `ipam` (geplant — noch nicht implementiert)

Org-weites **VPC IP Address Manager (IPAM)**: hierarchische CIDR-Verwaltung,
damit keine VPC-CIDRs überlappen (Pflicht für TGW-Routing).

## Core-Account
**Network-/Connectivity-Account** (gleicher Core wie `core-network`). IPAM wird
als delegierter Admin betrieben und org-weit geteilt.

## NARA-Ressourcen
- `aws_vpc_ipam` mit `operating_regions` (z.B. eu-central-1, eu-west-1).
- Pool-Hierarchie: Top-Pool → Regional-Pools → Environment-Pools
  (`aws_vpc_ipam_pool` + `aws_vpc_ipam_pool_cidr`), z.B.
  `10.0.0.0/8` → Region → `prod`/`dev`-Sub-Pools.
- `aws_ram_resource_share` der Pools an die Workloads-OU (analog `core-network`),
  damit Workload-Accounts CIDRs allokieren können.
- `aws_organizations_delegated_administrator` (`ipam.amazonaws.com`).

## Cross-account-Beziehung
- **→ `vpc`**: liefert `ipam_pool_ids`; VPCs ziehen ihre CIDRs per
  `ipv4_ipam_pool_id` statt hartkodiert.
- **→ `core-network`**: überlappungsfreie CIDRs sind Voraussetzung dafür, dass
  TGW-Routing zwischen Spokes überhaupt eindeutig funktioniert.
- Geteilt via RAM an die Workloads-OU → neue Accounts allokieren automatisch.
