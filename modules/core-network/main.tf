# modules/core-network/main.tf
# ---------------------------------------------------------------------------
# NTC/NARA-inspiriertes core-network Modul
# Inspiriert von: nuvibit/ntc-* (proprietaer)
#
# Zweck: zentraler Transit Gateway (TGW) als Netzwerk-Hub, segmentiert ueber
# mehrere Route Tables, und cross-account per RAM an die Workloads-OU geteilt.
# Konzeptioneller Ort: dedizierter "network"/"connectivity" Core-Account.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  # Zentrales "an/aus": ohne TGW wird im ganzen Modul nichts erzeugt.
  create = var.transit_gateway_enabled

  # RAM-Share nur, wenn TGW existiert UND Sharing gewuenscht ist.
  create_ram = local.create && var.enable_ram_share

  # Attachments werden nur verkabelt, wenn der TGW existiert.
  attachments = local.create ? var.vpc_attachments : {}

  # Propagation ist ein n:m-Verhaeltnis (ein Attachment -> mehrere Route Tables).
  # Terraform-Ressourcen brauchen aber flache Keys, darum flatten wir hier
  # "<attachment>-<routetable>" => {attachment, route_table}.
  attachment_propagations = merge([
    for att_key, att in local.attachments : {
      for rt in att.propagate_to :
      "${att_key}-${rt}" => {
        attachment_key = att_key
        route_table    = rt
      }
    }
  ]...)
}

# ---------------------------------------------------------------------------
# Transit Gateway
# ---------------------------------------------------------------------------
resource "aws_ec2_transit_gateway" "this" {
  count = local.create ? 1 : 0

  description     = "Central hub TGW for the landing zone"
  amazon_side_asn = var.amazon_side_asn

  # WARUM disable: per Default haengt AWS jedes neue Attachment automatisch in
  # EINE default Route Table und propagiert dorthin -> flaches Netz, jeder sieht
  # jeden. NARA will explizite Segmentierung (hub/spoke-prod/spoke-dev/onprem).
  # Durch Deaktivieren erzwingen wir, dass jedes Attachment bewusst einer RT
  # zugeordnet (association) und gezielt propagiert wird. Das ist DIE zentrale
  # Designentscheidung dieses Moduls.
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  # WARUM enable: Attachments aus anderen (geshareten) Accounts sollen nicht
  # manuell akzeptiert werden muessen. In einer Account-Factory-Welt mit vielen
  # Spokes waere manuelles Accept ein Skalierungs-/Toil-Problem.
  auto_accept_shared_attachments = "enable"

  # DNS-Resolution ueber den TGW hinweg (z.B. fuer zentrale Route53 Resolver).
  dns_support = "enable"

  # ECMP fuer VPN: erlaubt das Buendeln mehrerer VPN-Tunnel Richtung on-prem
  # fuer hoeheren Durchsatz/Redundanz.
  vpn_ecmp_support = "enable"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-tgw"
  })
}

# ---------------------------------------------------------------------------
# TGW Route Tables (Segmentierung)
# Eine RT je Segment. Die Trennung der Sicht passiert ueber unterschiedliche
# associations/propagations - NICHT ueber SecurityGroups.
# ---------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route_table" "this" {
  for_each = local.create ? toset(var.transit_gateway_route_tables) : toset([])

  transit_gateway_id = aws_ec2_transit_gateway.this[0].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-${each.value}"
  })
}

# ---------------------------------------------------------------------------
# VPC Attachments
# Verbindet eine Spoke-VPC mit dem TGW. subnet_ids sollten dedizierte
# TGW-/28-Subnetze je AZ sein (Best Practice: TGW-ENIs nicht mit Workload-
# Subnetzen mischen).
# ---------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = local.attachments

  transit_gateway_id = aws_ec2_transit_gateway.this[0].id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids

  # WARUM appliance_mode: bei stateful Inspection (Firewall) muss Hin- und
  # Rueckweg eines Flows ueber dieselbe AZ/Appliance laufen, sonst bricht die
  # Stateful-Pruefung. Nur fuer das Inspection-Attachment relevant.
  appliance_mode_support = each.value.appliance_mode ? "enable" : "disable"

  # WARUM explizit false: wir steuern association/propagation selbst (s.u.).
  # Doppelt-haelt-besser, falls die TGW-Defaults je geaendert werden.
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-att-${each.key}"
  })
}

# ---------------------------------------------------------------------------
# Route Table Associations
# Bestimmt, WELCHE RT ein Attachment benutzt -> "wohin darf dieses Attachment
# routen?". Genau EINE RT pro Attachment.
# ---------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each = local.attachments

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.associated_route_table].id
}

# ---------------------------------------------------------------------------
# Route Table Propagations
# Bestimmt, in WELCHE RTs die CIDRs eines Attachments eingetragen werden ->
# "wer darf dieses Attachment erreichen?". Beispiel-Muster:
#   spoke-prod propagiert nach hub  (Hub sieht Prod)
#   hub        propagiert nach spoke-prod + spoke-dev (alle sehen den Hub)
#   spoke-prod propagiert NICHT nach spoke-dev -> keine Ost-West-Verbindung.
# ---------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  for_each = local.attachment_propagations

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment_key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table].id
}

# ---------------------------------------------------------------------------
# Statische TGW-Routen
# Fuer alles, was Propagation nicht abdeckt: z.B. eine Default-Route 0.0.0.0/0
# in spoke-prod auf das Hub/Inspection-Attachment, oder Blackhole zum Blocken.
# ---------------------------------------------------------------------------
resource "aws_ec2_transit_gateway_route" "this" {
  for_each = local.create ? var.transit_gateway_static_routes : {}

  destination_cidr_block         = each.value.destination_cidr
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this[each.value.route_table].id

  # Blackhole-Route hat KEIN Ziel-Attachment; sonst zeigt die Route auf das
  # angegebene Attachment.
  blackhole = each.value.blackhole
  transit_gateway_attachment_id = (
    each.value.blackhole || each.value.attachment_key == null
    ? null
    : aws_ec2_transit_gateway_vpc_attachment.this[each.value.attachment_key].id
  )
}

# ---------------------------------------------------------------------------
# RAM - cross-account Sharing des TGW
# ---------------------------------------------------------------------------

# Org-weiter Schalter (normalerweise einmalig im Org-Baseline gesetzt).
# Ohne ihn kann RAM NICHT an OUs/Org teilen, sondern nur an einzelne Accounts.
resource "aws_ram_sharing_with_organization" "this" {
  count = var.enable_ram_organization_sharing ? 1 : 0
}

# Der Resource Share selbst (die "Huelle", an die Ressourcen + Principals haengen).
resource "aws_ram_resource_share" "tgw" {
  count = local.create_ram ? 1 : 0

  name = "${var.name_prefix}-tgw-share"

  # WARUM false: wir teilen NUR innerhalb der eigenen Organisation. external
  # principals waeren Accounts ausserhalb der Org - das wollen wir hart ausschliessen.
  allow_external_principals = false

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-tgw-share"
  })
}

# Verknuepft den TGW (die zu teilende Ressource) mit dem Share.
resource "aws_ram_resource_association" "tgw" {
  count = local.create_ram ? 1 : 0

  resource_arn       = aws_ec2_transit_gateway.this[0].arn
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}

# Principal = Workloads-OU. WARUM OU statt Account: jeder neue Account, der per
# Account-Factory in die OU gelegt wird, erbt den TGW-Share automatisch - kein
# manuelles Re-Sharing. Das ist die skalierbare NARA-Variante.
resource "aws_ram_principal_association" "workloads_ou" {
  count = local.create_ram && var.workloads_ou_arn != "" ? 1 : 0

  principal          = var.workloads_ou_arn
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}
