# ntc-showcase

Ein kleiner Terraform-Showcase rund um **NARA** ("Nuvibit Reference
Architecture"), eine AWS Multi-Account Landing Zone. Ich habe mir
docs.nuvibit.com angeschaut und mir daraus **ein** Thema herausgegriffen —
`core-network` —, um es wirklich zu verstehen statt an der Oberfläche zu bleiben.
Dieses eine Modul ist tief ausgearbeitet (Transit-Gateway-Hub mit
routing-basierter Segmentierung und RAM-Sharing, `fmt` + `validate` clean);
`organizations` und `account-factory` enthalten echten Ressourcen-Code, die
übrigen 8 Module sind begründete README-Stubs, die Schnittstelle und
Cross-Account-Beziehungen beschreiben. Es ist **kein deploybares Produkt** — kein
`apply`, kein State-Backend in Betrieb, sondern eine Lernübung an echtem Code.

---

## Warum dieses Projekt

Der NARA-Ansatz hat mich interessiert, also habe ich mir die Nuvibit-Docs
angeschaut und mir `core-network` herausgegriffen, um eines der Themen ernsthaft
durchzuarbeiten. Lieber **ein Modul, das ich Zeile für Zeile erklären kann, als
elf abgeschriebene** — deshalb ist nur dieses eine tief ausgearbeitet, und der
Rest ist als Schnittstelle skizziert statt als Fassade vorgetäuscht.
Network-Firewall-Inspection habe ich bewusst weggelassen; das wäre der nächste
Schritt. Die Entscheidungen dahinter stehen in
[`docs/DECISIONS.md`](docs/DECISIONS.md).

---

## Was ist NARA? (Kurz, für Leser ohne Nuvibit-Kontext)

NARA strukturiert eine AWS-Organisation in dedizierte **Core Accounts**, damit
Verantwortung, Blast Radius und Service-Quotas getrennt sind und Workloads nie in
einem Core-Account laufen:

1. **Org Management (Payer/Root)** — verwaltet die AWS Organization, OUs und
   org-weite Service Control Policies; bleibt ansonsten schlank.
2. **Log Archive** — write-once-Speicher (WORM) für org-weites CloudTrail/Config,
   bewusst getrennt vom analysierenden Audit-Account (Separation of Duties).
3. **Security Tooling / Audit** — delegierter Administrator für GuardDuty,
   Security Hub und Access Analyzer; aggregiert Findings org-weit.
4. **Connectivity / Network** — der Netzwerk-Hub (Transit Gateway, IPAM, zentrales
   DNS), vom Payer getrennt wegen eigener Quotas und eigenem Blast Radius.

---

## Repo-Struktur

```
ntc-showcase/
├── README.md                      # dieser A-Z-Einstieg
├── main.tf                        # Root: Provider, S3-Backend-Block, Data-Sources
├── variables.tf                   # Root-Eingabevariablen (Org, Accounts, Feature-Flags)
├── outputs.tf                     # Root-Outputs (verweisen auf die Modul-Komposition)
├── .gitignore                     # ignoriert .terraform/, State, *.tfvars, …
├── docs/
│   ├── ARCHITECTURE.md            # Core Accounts, Modul-Mapping, Abhängigkeitsketten
│   ├── DECISIONS.md               # ADRs (Meta-Entscheidung + core-network + Scope-Grenze)
│   ├── architecture-diagram.html  # technisches Dark-Theme-SVG, eigenständig (keine ext. Deps)
│   └── landing-zone-erklaert.html # einsteigerfreundliche, einfache Erklärung
├── examples/
│   └── complete-landing-zone/
│       └── main.tf                # illustrative Verdrahtung aller Module (Skizze, s.u.)
└── modules/
    ├── core-network/              # IMPLEMENTIERT: TGW-Hub, Route Tables, RAM-Share
    ├── organizations/             # IMPLEMENTIERT: Organization, OUs, Basis-SCPs
    ├── account-factory/           # IMPLEMENTIERT (root-gekoppelt): Account-Erstellung
    ├── vpc/                       # STUB: Spoke-VPCs + TGW-Attachment
    ├── ipam/                      # STUB: org-weites VPC IP Address Management
    ├── route53/                   # STUB: private Hosted Zones + Resolver
    ├── identity-center/           # STUB: IAM Identity Center (SSO) / Permission Sets
    ├── log-archive/               # STUB: zentrales WORM-Log-Archiv
    ├── security-tooling/          # STUB: GuardDuty / Security Hub / Access Analyzer
    ├── guardrails/                # STUB: erweiterte SCPs + Config Org Rules
    └── parameters/                # STUB: SSM-Parameter-Verteilung (Service-Discovery)
```

Nur `core-network` hat vollständige `main.tf` + `variables.tf` + `outputs.tf` +
`README.md`. `organizations` und `account-factory` haben eine `main.tf` (Variablen
und Outputs inline). Die 8 Stubs bestehen ausschließlich aus einer `README.md`.

---

## Scope — Modul-Übersicht

| Modul | Status | Core-Account | Kurzbeschreibung |
|---|---|---|---|
| `core-network` | ✅ implementiert | Connectivity / Network | TGW-Hub, Route Tables (`hub`/`spoke-prod`/`spoke-dev`/`onprem`), VPC-Attachments, RAM-Share an die Workloads-OU. `fmt` + `validate` clean. |
| `organizations` | ✅ implementiert | Org Management | Organization, OU-Struktur, Trusted-Service-Access, Basis-SCPs (`DenyRootUserAccess`, `RequireMFAForConsole`). `validate` standalone clean. |
| `account-factory` | ✅ implementiert ✱ | Org Management | Erstellt Audit-/Log-Archive-/Workload-Accounts + `OrganizationAccountAccessRole`. An Root gekoppelt → nicht standalone `validate`. |
| `vpc` | 📝 Stub | Workload-Accounts | Spoke-VPCs pro Account, CIDR aus IPAM, Attachment an den geteilten TGW. |
| `ipam` | 📝 Stub | Connectivity / Network | Org-weites VPC IPAM, Pool-Hierarchie, per RAM geteilt. |
| `route53` | 📝 Stub | Connectivity / Network | Private Hosted Zones + zentrale Resolver-Endpoints im Hub. |
| `identity-center` | 📝 Stub | Org Management | IAM Identity Center, Permission Sets, Account-/OU-Zuweisungen. |
| `log-archive` | 📝 Stub | Log Archive | Organization-CloudTrail + Config in WORM-S3-Bucket. |
| `security-tooling` | 📝 Stub | Security Tooling / Audit | GuardDuty / Security Hub / Access Analyzer, delegiert an Audit. |
| `guardrails` | 📝 Stub | Org Management / Audit | Erweiterte SCPs + Config Org Managed Rules, OU-differenziert. |
| `parameters` | 📝 Stub | zentral (Mgmt/Network) | Landing-Zone-Werte als SSM-Parameter, cross-account verteilt. |

✱ Siehe [Bekannte Scope-Grenzen](#bekannte-scope-grenzen). Stubs sind echte
README-Stubs — sie beschreiben, *was* gebaut würde, ohne zu behaupten, es sei gebaut.

---

## Schnellstart

**Voraussetzungen:** Terraform `>= 1.6`. Kein AWS-Account und keine Credentials
nötig — alle Befehle laufen offline mit `-backend=false`, ohne `plan`/`apply`.

Die folgenden Befehle sind copy-paste-fähig (Fish-Shell, aus dem Repo-Wurzelverzeichnis):

```fish
# core-network — das tief ausgearbeitete Modul (fmt + validate clean)
cd modules/core-network
terraform init -backend=false
terraform fmt -check
terraform validate
cd ../..

# organizations — validiert ebenfalls standalone
cd modules/organizations
terraform init -backend=false
terraform fmt -check
terraform validate
cd ../..
```

`account-factory` und die Root-/Example-Komposition validieren bewusst **nicht**
isoliert — warum, steht direkt darunter.

---

## In 5 Minuten lesen (geführter Pfad für Reviewer)

1. **Dieses README** — Scope und Erwartung setzen (~1 Min).
2. **[`docs/architecture-diagram.html`](docs/architecture-diagram.html)** — im
   Browser öffnen: Core Accounts, TGW-Hub mit den Route Tables und RAM-Share an
   die Workloads-OU auf einen Blick (~1 Min).
3. **[`modules/core-network/main.tf`](modules/core-network/main.tf)** — das
   Substanz-Modul. Die `WARUM`-Kommentare erklären jede Designentscheidung direkt
   am Code (~2 Min).
4. **[`docs/DECISIONS.md`](docs/DECISIONS.md)** — die ADRs, inklusive der ehrlichen
   Scope-Grenze (Network-Firewall-Inspection bewusst draußen) (~1 Min).

Tiefer: **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** (Account-Mapping +
Abhängigkeitsketten `ipam → vpc → core-network` und `account-factory →
organizations`) und die `README.md` jedes Stubs unter `modules/<name>/`.

---

## Bekannte Scope-Grenzen

Bewusst offengelegt, damit klar ist, was *nicht* funktioniert:

- **`account-factory` ist root-gekoppelt + zwei bekannte apply-Schwächen.** Das
  Modul referenziert `data.aws_partition.current` und
  `data.aws_caller_identity.current`, die nur im Root-Modul (`main.tf`) deklariert
  sind — die Ressourcenlogik ist vorhanden, das Modul besteht `terraform validate`
  deshalb nicht isoliert. Zwei weitere Punkte wären erst **bei `apply`** relevant
  (kein `apply` vorgesehen), sind aber offen benannt:
  (1) `aws_iam_role.account_baseline` wird per `for_each` mit demselben Namen
  `OrganizationAccountAccessRole` im **selben** (Management-)Account angelegt →
  Namenskonflikt; korrekt wäre die Erstellung per Provider-Alias im jeweiligen
  Member-Account. (2) `time_sleep.wait_for_accounts` ist deklariert, aber die
  Baseline-Rolle hängt nicht per `depends_on` daran — der Wait greift derzeit nicht.
  Beides ist der nächste saubere Fix.
- **Root + Example sind eine Verdrahtungs-Skizze.** Das Root-`main.tf` enthält nur
  Provider, den `backend "s3"`-Block und Data-Sources; die eigentliche
  Modul-Komposition liegt illustrativ in
  [`examples/complete-landing-zone/main.tf`](examples/complete-landing-zone/main.tf).
  Diese Komposition referenziert die 8 Stub-Module und eine nicht deklarierte
  Variable (`vpc_cidr_blocks`) und ist als Ganzes nicht `validate`-clean. Sie
  dient dazu, die Modul-Schnittstellen und Abhängigkeiten lesbar zu machen.
- **Keine Network-Firewall-Inspection.** Eine zentrale Inspection-VPC (stateful
  Egress/Ost-West-Prüfung) ist nicht implementiert. Das Interface ist nur
  vorbereitet: `network_firewall_enabled` wird akzeptiert, aber ignoriert, und
  `appliance_mode_support` ist pro Attachment schaltbar. Das wäre der nächste Layer.
- **Kein `apply`, kein Deploy.** Der `backend "s3"`-Block ist Konfiguration auf
  dem Papier — es gibt kein bereitgestelltes State-Bucket. Alle Verify-Befehle
  laufen offline.

---

## Dokumentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — NARA Core Accounts,
  Modul-Mapping, Abhängigkeitsketten, implementiert vs. Stub.
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — ADRs: Meta-Entscheidung (ein Modul
  tief), die `core-network`-Entscheidungen, Scope-Grenze.
- [`docs/architecture-diagram.html`](docs/architecture-diagram.html) — technisches
  Diagramm (Dark-Theme, eigenständiges SVG, keine externen Abhängigkeiten).
- [`docs/landing-zone-erklaert.html`](docs/landing-zone-erklaert.html) — einfache,
  einsteigerfreundliche Erklärung der Landing Zone (ergänzt das technische Diagramm).
