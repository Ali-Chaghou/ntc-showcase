# Architecture Decision Records — ntc-showcase

Knappe ADRs im Stil *Kontext / Entscheidung / Tradeoff*. Sie dokumentieren nur
Entscheidungen, die sich im vorhandenen Code wiederfinden, plus eine ehrliche
Scope-Grenze.

---

## ADR-001 — Ein Modul tief statt zwölf halbfertig

**Kontext.** Eine vollständige NARA-Landing-Zone hätte ~11 Module. In der
verfügbaren Zeit (Interview-Vorbereitung) lassen sich entweder viele Module
oberflächlich oder wenige Module ernsthaft bauen.

**Entscheidung.** Ein Modul — `core-network` — wird tief ausgearbeitet
(`terraform fmt` + `terraform validate` clean, kommentiertes WARUM, Beispiel,
Feature-Flags, Validierungen). `organizations` und `account-factory` haben
funktionierende Ressourcenlogik. Die übrigen 8 Module sind **begründete
README-Stubs**: jede README benennt Core-Account, die konkreten NARA-Ressourcen
und die Cross-Account-Beziehungen — also die Schnittstelle, nicht die Fassade.

**Tradeoff.** Die Landing Zone ist nicht deploybar; der Root (`/main.tf`) ist
eine Verdrahtungs-Skizze, die als Ganzes nicht `validate`-clean ist. Gewonnen
wird ein Modul, das ich Zeile für Zeile verteidigen kann, statt zwölf, die nur
aus der Distanz funktionieren. Für ein Gespräch über *Verständnis* ist Tiefe
mehr wert als Breite.

---

## ADR-002 — TGW-Default-Association und -Propagation deaktivieren

**Kontext.** Per Default hängt AWS jedes neue TGW-Attachment automatisch in *eine*
Default-Route-Table und propagiert dorthin. Ergebnis: ein flaches Netz, in dem
jedes Attachment jedes andere erreicht.

**Entscheidung.** `default_route_table_association = "disable"` und
`default_route_table_propagation = "disable"` am `aws_ec2_transit_gateway`. Damit
muss jedes Attachment bewusst einer Route Table zugeordnet und gezielt
propagiert werden. Das ist die zentrale Entscheidung des Moduls — alle anderen
Routing-Entscheidungen bauen darauf auf.

**Tradeoff.** Mehr expliziter Konfigurationsaufwand (jede Association/Propagation
muss deklariert werden) gegen echte, routing-basierte Segmentierung. Vergessene
Propagation = stiller Connectivity-Verlust statt versehentlicher Vollvermaschung
— der bewusst sicherere Fehlermodus.

---

## ADR-003 — Eine Route Table pro Segment

**Kontext.** Prod- und Dev-Workloads sollen denselben Hub nutzen (zentrale
Dienste, Egress), sich aber gegenseitig nicht sehen. On-prem (VPN/DX) ist ein
weiteres Segment.

**Entscheidung.** Je Segment eine TGW Route Table:
`hub` / `spoke-prod` / `spoke-dev` / `onprem` (parametrisierbar über
`transit_gateway_route_tables`). Segmentierung passiert über *Routing*, nicht
über Security Groups oder NACLs.

**Tradeoff.** Mehr Route Tables zu verwalten gegen eine klar lesbare
Isolations-Topologie, die unabhängig von SG/NACL auf jeder Ebene gilt.
Ost-West zwischen Prod und Dev ist by design unmöglich, weil schlicht keine
Route existiert — nicht weil eine Regel sie verbietet.

---

## ADR-004 — Association ≠ Propagation als zwei getrennte Steuerungen

**Kontext.** "Wohin darf ein Attachment routen?" und "wer darf ein Attachment
erreichen?" sind zwei verschiedene Fragen, die AWS über zwei verschiedene
Mechanismen beantwortet.

**Entscheidung.** Strikte Trennung im Modul-Interface (`vpc_attachments`):

- **Association** (`associated_route_table`) — genau **eine** RT pro Attachment:
  bestimmt die Routing-*Sicht* des Attachments (wohin darf es?).
- **Propagation** (`propagate_to`) — eine **Liste** von RTs: in welche RTs die
  CIDRs des Attachments eingetragen werden (wer darf es erreichen?).

Die n:m-Propagation wird in `locals.attachment_propagations` zu flachen Keys
`"<attachment>-<routetable>"` ge-flattet, weil Terraform-Ressourcen flache
`for_each`-Keys brauchen.

**Tradeoff.** Konzeptionell anspruchsvoller als ein einzelnes "connect this"-Flag
— aber genau diese Trennung *ist* das Segmentierungswerkzeug. Beispiel:
`prod-app` assoziiert mit `spoke-prod` und propagiert nur nach `hub` → Prod sieht
den Hub, aber `spoke-prod` enthält keine Route zum Dev-Attachment → keine
Ost-West-Verbindung.

---

## ADR-005 — `auto_accept_shared_attachments = enable`

**Kontext.** In einer Account-Factory-Welt entstehen laufend neue Spokes, deren
VPCs sich an den geteilten TGW hängen. Cross-Account-Attachments müssen
normalerweise im TGW-Owner-Account manuell akzeptiert werden.

**Entscheidung.** `auto_accept_shared_attachments = "enable"` am TGW.

**Tradeoff.** Bequemlichkeit/Skalierung gegen ein manuelles Gate: jedes neue
Attachment ist sofort live, ohne Toil pro Spoke. Vertretbar, weil der TGW
ausschließlich innerhalb der eigenen Organisation geteilt wird (siehe ADR-006) —
der Kreis möglicher Attacher ist also bereits org-intern begrenzt.

---

## ADR-006 — RAM-Share an die Workloads-OU statt an Account-IDs

**Kontext.** Der TGW muss cross-account nutzbar sein. RAM kann an einzelne
Account-IDs *oder* an eine Organizational Unit teilen.

**Entscheidung.** Primärer Principal ist die **Workloads-OU**
(`aws_ram_principal_association` auf `workloads_ou_arn`). Eine optionale
Account-ID-Liste (`workload_account_ids`) bleibt als Nebenweg im Interface, ist
aber nicht der Standard. Zusätzlich `allow_external_principals = false` am
Resource Share.

**Tradeoff.** Sharing an eine OU setzt voraus, dass "RAM sharing within AWS
Organizations" org-weit aktiv ist (im Modul über `enable_ram_organization_sharing`
gekapselt, default `false`, weil es ein einmaliger Org-Baseline-Schalter ist).
Dafür erbt **jedes aktuelle und zukünftige** Account in der OU den TGW-Share
automatisch — kein Re-Sharing pro neuem Account-Factory-Account. `allow_external_principals = false`
schließt Accounts außerhalb der Org hart aus: der Komfort aus ADR-005 bleibt
damit auf den org-internen Kreis begrenzt.

---

## ADR-007 — Scope-Grenze: keine Network-Firewall-Inspection

**Kontext.** Der logische nächste Layer über einem segmentierten Hub-and-Spoke
ist zentrale **Traffic-Inspection**: eine Inspection-VPC am Hub, durch die der
Ost-West- und Egress-Verkehr stateful geprüft wird.

**Entscheidung.** Diese Schicht ist **bewusst nicht** implementiert. Das Modul
bereitet das Interface nur vor:

- `network_firewall_enabled` wird als Input **akzeptiert, aber ignoriert** — der
  Variablen-Kommentar sagt das explizit, damit eine spätere Erweiterung das
  Modul-Interface nicht bricht.
- `appliance_mode_support` ist pro Attachment schaltbar (`appliance_mode`), weil
  stateful Inspection erfordert, dass Hin- und Rückweg eines Flows über dieselbe
  AZ/Appliance laufen. Der Schalter existiert, das dazugehörige Inspection-Ziel
  nicht.

Vollständig wäre der nächste Layer: eine Inspection-VPC mit `aws_networkfirewall_firewall`,
ein Inspection-Attachment im `hub`-Segment, und statische Default-Routen
(`0.0.0.0/0`) der Spoke-RTs auf dieses Attachment.

**Tradeoff.** Der Showcase endet bei *Segmentierung* statt *Inspection*. Ehrlicher,
als eine halbe Firewall zu zeigen — und das vorbereitete Interface macht die
Grenze sichtbar, statt sie zu verstecken.
