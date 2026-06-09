# Module: `core-network`

NTC/NARA-inspirierter Netzwerk-Hub: ein **Transit Gateway (TGW)** mit
segmentierten Route Tables, parametrisierbaren VPC-Attachments und
cross-account **RAM-Sharing** an die Workloads-OU.

> Showcase / Interview-Vorbereitung. **Kein `apply`** vorgesehen — das Modul
> besteht `terraform fmt` und `terraform validate`.

## Wo lebt dieses Modul (Core-Account)?

In NARA gehört der TGW in einen **dedizierten Network-/Connectivity-Account**,
nicht ins Management-Account:

- **Blast Radius**: Netzwerk-Änderungen sollen nicht im Payer/Root-Account passieren.
- **Trennung der Concerns**: eigenes IAM, eigene Service-Quotas (TGW-Attachments
  sind quota-limitiert), eigene Cost-Allocation.
- Das Management-Account bleibt schlank (Organizations, Billing).

Die Spokes (Workload-VPCs) liegen in den Workload-Accounts und werden über
**RAM** auf den geteilten TGW attached.

## Designentscheidungen (das WARUM)

| Entscheidung | Warum NARA es so macht |
|---|---|
| `default_route_table_association = "disable"` | Sonst landet jedes Attachment automatisch in **einer** Default-RT → flaches Netz, jeder sieht jeden. Deaktivieren erzwingt explizite Segmentierung. |
| `default_route_table_propagation = "disable"` | Gleiche Logik für die Propagation: CIDRs sollen nur dort auftauchen, wo wir es bewusst wollen. |
| Mehrere Route Tables (`hub`, `spoke-prod`, `spoke-dev`, `onprem`) | Segmentierung **über Routing** statt SG/NACL. Prod und Dev können denselben Hub nutzen, sehen sich aber gegenseitig nicht (keine Ost-West-Route). |
| `association` ≠ `propagation` | `association` = „wohin darf dieses Attachment routen?“ (genau 1 RT). `propagation` = „wer darf dieses Attachment erreichen?“ (n RTs). Diese Trennung ist der Kern der Segmentierung. |
| `auto_accept_shared_attachments = "enable"` | In einer Account-Factory mit vielen Spokes wäre manuelles Accept jedes Attachments Toil und nicht skalierbar. |
| RAM-Principal = **OU-ARN** statt Account-IDs | Neue Accounts in der Workloads-OU erben den Share **automatisch** — kein Re-Sharing pro Account. |
| `allow_external_principals = false` | TGW darf nur **innerhalb** der eigenen Organisation geteilt werden. |
| `appliance_mode_support` (optional) | Für stateful Inspection muss Hin-/Rückweg über dieselbe AZ/Appliance laufen — sonst bricht die stateful Firewall. |

## Segmentierungs-Beispiel (Hub-and-Spoke mit Prod/Dev-Isolation)

```hcl
module "core_network" {
  source = "../../modules/core-network"

  transit_gateway_enabled = true
  amazon_side_asn         = 64512

  # RAM an die Workloads-OU (ARN aus dem organizations-Modul)
  enable_ram_share = true
  workloads_ou_arn = "arn:aws:organizations::111122223333:ou/o-abc123/ou-abcd-11112222"

  vpc_attachments = {
    # Prod-VPC: assoziiert mit spoke-prod, sichtbar fuer hub
    "prod-app" = {
      vpc_id                 = "vpc-prod111"
      subnet_ids             = ["subnet-pa", "subnet-pb"]
      associated_route_table = "spoke-prod"
      propagate_to           = ["hub"]
    }
    # Dev-VPC: assoziiert mit spoke-dev, sichtbar fuer hub
    "dev-app" = {
      vpc_id                 = "vpc-dev111"
      subnet_ids             = ["subnet-da", "subnet-db"]
      associated_route_table = "spoke-dev"
      propagate_to           = ["hub"]
    }
    # Shared-Services-/Hub-VPC: assoziiert mit hub, sichtbar fuer beide Spokes
    "shared-svc" = {
      vpc_id                 = "vpc-hub111"
      subnet_ids             = ["subnet-ha", "subnet-hb"]
      associated_route_table = "hub"
      propagate_to           = ["spoke-prod", "spoke-dev"]
    }
  }

  # Default-Route der Spokes Richtung Hub (z.B. fuer zentralen Egress/Inspection)
  transit_gateway_static_routes = {
    "prod-default-to-hub" = {
      route_table      = "spoke-prod"
      destination_cidr = "0.0.0.0/0"
      attachment_key   = "shared-svc"
    }
    "dev-default-to-hub" = {
      route_table      = "spoke-dev"
      destination_cidr = "0.0.0.0/0"
      attachment_key   = "shared-svc"
    }
  }

  tags = { Module = "core-network" }
}
```

**Resultierende Sicht:**
`prod-app` ↔ `shared-svc` ✔ · `dev-app` ↔ `shared-svc` ✔ · `prod-app` ↔ `dev-app` ✘
(weil prod nur nach `hub` propagiert und in `spoke-prod` keine Route auf das
dev-Attachment existiert).

## Wichtige Inputs

| Name | Typ | Default | Zweck |
|---|---|---|---|
| `transit_gateway_enabled` | bool | `true` | Master-Schalter |
| `amazon_side_asn` | number | `64512` | BGP-ASN der Amazon-Seite (validiert) |
| `transit_gateway_route_tables` | list(string) | `[hub, spoke-prod, spoke-dev, onprem]` | Segmente |
| `vpc_attachments` | map(object) | `{}` | Spoke-Attachments + Routing-Zuordnung |
| `transit_gateway_static_routes` | map(object) | `{}` | statische / Blackhole-Routen |
| `enable_ram_share` | bool | `true` | RAM-Share anlegen |
| `workloads_ou_arn` | string | `""` | RAM-Principal (OU) |
| `enable_ram_organization_sharing` | bool | `false` | org-weiter RAM-Schalter (s.u.) |

## Outputs

`transit_gateway_id`, `transit_gateway_arn`, `transit_gateway_route_table_ids`
(map), `vpc_attachment_ids` (map), `ram_resource_share_arn`.

## Voraussetzung: RAM-Sharing in der Organisation

Sharing an eine OU funktioniert nur, wenn **„RAM sharing within AWS
Organizations“** aktiv ist. Das ist ein **einmaliger, org-weiter** Schalter und
wird in NARA im Org-/Management-Baseline gesetzt (zudem RAM als trusted service
in Organizations — siehe `modules/organizations`, `ram.amazonaws.com`). Falls
dieses Modul den Owner-Account verwaltet, kann man es per
`enable_ram_organization_sharing = true` hier einschalten.

## Validierung

```bash
cd modules/core-network
terraform init -backend=false
terraform fmt -check
terraform validate
```
