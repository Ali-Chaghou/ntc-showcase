# Architektur — ntc-showcase

NARA-inspirierte ("Nuvibit Reference Architecture") Multi-Account Landing Zone
als Terraform-Showcase. Dieses Dokument beschreibt **nur, was im Repo wirklich
existiert** — implementierter Code wird klar von README-Stubs getrennt.

> Showcase / Interview-Vorbereitung, kein fertiges Produkt. Kein `apply`,
> kein Deploy vorgesehen.

---

## 1. Status auf einen Blick

| Modul | Status | Verifiziert |
|---|---|---|
| `core-network` | **IMPLEMENTIERT** (tief ausgearbeitet) | `terraform fmt` clean, `terraform validate` clean ✔ |
| `organizations` | **IMPLEMENTIERT** (Ressourcenlogik) | `terraform validate` standalone clean ✔ |
| `account-factory` | **IMPLEMENTIERT** (Ressourcenlogik) | an Root gekoppelt → validiert **nicht** standalone ✱ |
| `vpc` | **STUB** (nur README) | — |
| `ipam` | **STUB** (nur README) | — |
| `route53` | **STUB** (nur README) | — |
| `identity-center` | **STUB** (nur README) | — |
| `log-archive` | **STUB** (nur README) | — |
| `security-tooling` | **STUB** (nur README) | — |
| `guardrails` | **STUB** (nur README) | — |
| `parameters` | **STUB** (nur README) | — |

✱ `account-factory/main.tf` referenziert `data.aws_partition.current` und
`data.aws_caller_identity.current`, die nur im **Root-Modul** (`/main.tf`)
deklariert sind. Die Ressourcenlogik (Account-Erstellung, Baseline-Rolle) ist
vorhanden, das Modul ist aber bewusst an den Root-Kontext gekoppelt und besteht
`terraform validate` daher nicht isoliert. Zwei Punkte wären zudem erst bei
`apply` relevant (kein `apply` vorgesehen, offen benannt in der README):
die Baseline-Rolle `OrganizationAccountAccessRole` würde per `for_each` namens­gleich
im selben Account kollidieren (korrekt: Provider-Alias je Member-Account), und
`time_sleep.wait_for_accounts` ist nicht per `depends_on` an die Rolle verdrahtet.

**Root-Konfiguration (`/main.tf`):** enthält nur Provider, den `backend "s3"`-Block
und Data-Sources (`aws_caller_identity`, `aws_partition`, `aws_region`) — **keine**
`module`-Blöcke. Die eigentliche Modul-Komposition liegt illustrativ in
[`examples/complete-landing-zone/main.tf`](../examples/complete-landing-zone/main.tf):
sie verdrahtet alle 11 Module und zeigt, wie die Landing Zone komponiert *wäre*.
Diese Komposition referenziert die Stub-Module (ohne `.tf`) und eine nicht
deklarierte Variable `vpc_cidr_blocks` und ist deshalb als Ganzes eine
**Verdrahtungs-Skizze**, nicht `validate`-clean. Sie dient dazu, die
Modul-Schnittstellen und Abhängigkeiten lesbar zu machen.

---

## 2. NARA Core Accounts — und welches Modul wo lebt

NARA trennt die Landing Zone in dedizierte Core-Accounts, damit Blast Radius,
IAM und Service-Quotas pro Verantwortungsbereich isoliert sind. Workloads laufen
nie in einem Core-Account.

### Org Management (Payer / Root)
Das schlanke "Wurzel"-Account. Verwaltet Organisation, OUs und org-weite Policies.

- **`organizations`** *(IMPLEMENTIERT)* — `aws_organizations_organization` mit
  Trusted-Service-Access (CloudTrail, Config, GuardDuty, SecurityHub,
  Access Analyzer, RAM, EC2, RDS), OU-Struktur (`security`, `workloads`,
  `sandbox` + verschachtelte `prod`/`staging`/`dev`/`sandbox`) und Basis-SCPs
  (`DenyRootUserAccess`, `RequireMFAForConsole`).
- **`account-factory`** *(IMPLEMENTIERT, root-gekoppelt)* — die Organizations-API
  läuft im Payer-Account; erstellt Audit-, Log-Archive- und Workload-Accounts
  (`aws_organizations_account`) und legt je Workload eine
  `OrganizationAccountAccessRole` mit ExternalId-Condition an.
- **`guardrails`** *(STUB)* — SCPs sind nur hier attachbar; erweitert die
  Basis-SCPs zu einem OU-differenzierten Set.
- **`identity-center`** *(STUB)* — IAM Identity Center ist org-weit, läuft im
  Management- oder einem delegierten Admin-Account.
- **`parameters`** *(STUB)* — schreibt Landing-Zone-Werte zentral und verteilt
  sie per SSM cross-account.

### Log Archive (eigenes Account in der Security-OU)
Write-once-Speicher, getrennt vom analysierenden Audit-Account (Separation of Duties).

- **`log-archive`** *(STUB)* — Organization-CloudTrail + Config-Aggregator,
  Ziel-Bucket mit Object Lock (WORM), Versioning, SSE-KMS und Org-Principal-Policy.

### Security Tooling / Audit (delegierter Admin)
Das Security-Team arbeitet eigenständig; Findings landen nicht im Payer-Account.

- **`security-tooling`** *(STUB)* — GuardDuty, Security Hub, IAM Access Analyzer
  als Organization-Admin (delegiert an Audit), `auto_enable` für neue Accounts.
- **`guardrails`** *(STUB)* — der detektive Teil (Config Org Managed Rules) wird
  org-weit über Audit ausgerollt.

### Connectivity / Network (dedizierter Network-Account)
Netzwerk-Hub, vom Payer getrennt (eigene Quotas, eigener Blast Radius).

- **`core-network`** *(IMPLEMENTIERT)* — zentraler Transit Gateway, segmentierte
  Route Tables (`hub`/`spoke-prod`/`spoke-dev`/`onprem`), parametrisierbare
  VPC-Attachments, RAM-Share an die Workloads-OU.
- **`ipam`** *(STUB)* — org-weites VPC IPAM, Pool-Hierarchie, per RAM geteilt.
- **`route53`** *(STUB)* — private Hosted Zones + zentrale Resolver-Endpoints im Hub.

### Workload-Accounts (keine Core-Accounts)
Die Spokes selbst.

- **`vpc`** *(STUB)* — läuft pro Workload-Account (prod/staging/dev), zieht CIDRs
  aus IPAM und attached die VPC an den geteilten TGW.

---

## 3. Modul-Abhängigkeitsketten

Pfeil `A → B` heißt: **A hängt von B ab / konsumiert dessen Output**. Die Pfeile
folgen der Verdrahtung in `examples/complete-landing-zone/main.tf` und den
Stub-READMEs.

### Netzwerk-Kette: `ipam → vpc → core-network`

```
ipam  ──(ipam_pool_ids)──►  vpc  ──(vpc_id + tgw-subnet_ids)──►  core-network
```

- **`vpc → ipam`** — die VPC zieht ihren CIDR per `ipv4_ipam_pool_id` aus einem
  IPAM-Pool statt hartkodiert. Begründung: org-weit überlappungsfreie CIDRs sind
  Voraussetzung für eindeutiges TGW-Routing zwischen Spokes.
- **`core-network → vpc`** — ein `aws_ec2_transit_gateway_vpc_attachment` braucht
  `vpc_id` und konkrete `subnet_ids` (dedizierte TGW-`/28` je AZ). Diese liefert
  das vpc-Modul; Association/Propagation werden zentral im core-network gesetzt.

> Gegenrichtung (im Code als RAM, nicht als TF-Dependency): `core-network` teilt
> den TGW per RAM an die Workloads-OU, damit das `vpc`-Modul ihn überhaupt
> attachen kann. Konzeptionell ist die Beziehung also wechselseitig; die obige
> Pfeilrichtung folgt dem Datenfluss der Attachment-Inputs.

### Org-Kette: `account-factory → organizations`

```
account-factory  ──(organization_id + ou_ids)──►  organizations
```

- **`account-factory → organizations`** — die Factory braucht `organization_id`
  und `ou_ids` aus dem organizations-Modul: `ou_ids["security"]` /
  `ou_ids["workloads"]` werden als `parent_id` neuer Accounts gesetzt, und die
  `organization_id` geht in die ExternalId der `OrganizationAccountAccessRole`.
  Begründung: die OU-Struktur muss existieren, bevor Accounts hineingelegt werden.

### Folge-Abhängigkeiten (zur Einordnung, Module sind Stubs)

- `core-network → account-factory` — konsumiert `workload_account_ids` (optionale
  RAM-Principals; Primärweg bleibt die OU).
- `security-tooling / log-archive / guardrails → organizations` — konsumieren
  `ou_ids` als Ziel für Delegation, SCPs und Org-Trail.
- `route53 → vpc` — konsumiert `vpc_ids` für Zone-Associations.
- `parameters → (alle)` — konsumiert Outputs und verteilt sie als SSM-Parameter.

---

## 4. Was bewusst NICHT enthalten ist

- **Network-Firewall-Inspection** (Inspection-VPC, zentrales Egress über eine
  Appliance, `0.0.0.0/0`-Default der Spokes auf das Inspection-Attachment) ist
  **nicht** implementiert. Das Interface ist vorbereitet — die Variable
  `network_firewall_enabled` wird akzeptiert (aber ignoriert) und
  `appliance_mode_support` ist pro Attachment schaltbar — die eigentliche
  Inspection-Schicht wäre der nächste Layer. Siehe
  [DECISIONS.md](DECISIONS.md) (Scope-Grenze).
- Kein State-Backend in Betrieb, kein `apply`. Der `backend "s3"`-Block in
  `/main.tf` ist Konfiguration auf dem Papier, kein bereitgestelltes Bucket.

---

Details und das WARUM hinter den Entscheidungen: [DECISIONS.md](DECISIONS.md).
Visuelle Übersicht: [architecture-diagram.html](architecture-diagram.html).
