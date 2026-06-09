# Module: `vpc` (geplant — noch nicht implementiert)

Erzeugt die **Spoke-VPCs** in den Workload-Accounts und attached sie an den
zentralen TGW aus `core-network`.

## Core-Account
Läuft **pro Workload-Account** (prod/staging/dev), provisioniert via
cross-account `assume_role` (`OrganizationAccountAccessRole`). Der TGW selbst
liegt im Network-Account und wird per RAM hereingereicht.

## NARA-Ressourcen
- `aws_vpc` mit CIDR aus **IPAM** (`ipam_pool_ids` → `ipv4_ipam_pool_id`,
  statt hartkodierter CIDRs → keine Überlappungen org-weit).
- `aws_subnet` je AZ in 3 Ebenen: `private` (Workloads), `public` (nur wo nötig),
  dediziertes `tgw` /28 je AZ (TGW-ENIs getrennt halten).
- `aws_ec2_transit_gateway_vpc_attachment` auf den **geshareten** TGW
  (subnet_ids = die tgw-Subnetze).
- `aws_route_table` + Default-Route `0.0.0.0/0` → `transit_gateway_id` (zentraler
  Egress/Inspection statt NAT-GW pro VPC).
- Optional `aws_flow_log` → zentrales Log-Archive.

## Cross-account-Beziehung
- **← `core-network`**: konsumiert `transit_gateway_id` (via RAM-Share an die Workloads-OU).
- **← `ipam`**: konsumiert `ipam_pool_ids` für die CIDR-Zuteilung.
- **→ `core-network`**: liefert `vpc_id` + tgw-`subnet_ids` als Input für
  `vpc_attachments` (association/propagation passiert zentral im Hub-Account).
- **→ `route53`**: VPC-IDs für die Verknüpfung privater Hosted Zones.
