# modules/core-network/variables.tf
# ---------------------------------------------------------------------------
# NTC/NARA-inspiriertes core-network Modul.
# Das Modul lebt konzeptionell im "network" / "connectivity" Core-Account
# (in NARA ein dediziertes Account, NICHT das Management-Account), weil
# Netzwerk-Hub und Workloads sauber getrennt sein muessen (blast radius,
# eigenes IAM, eigene Quotas). Siehe README.md.
# ---------------------------------------------------------------------------

variable "name_prefix" {
  description = "Naming-Praefix nach Konvention ntc-<domain>-<component>. Domain hier = core-network."
  type        = string
  default     = "ntc-core-network"
}

# ---------------------------------------------------------------------------
# Feature-Flags
# Wir spiegeln die Flags des root-Configs wider, damit das gesamte Netzwerk
# per Schalter aktiviert/deaktiviert werden kann (z.B. Sandbox-Stage ohne TGW).
# ---------------------------------------------------------------------------

variable "transit_gateway_enabled" {
  description = "Master-Schalter: erstellt TGW + Route Tables + RAM-Share nur wenn true."
  type        = bool
  default     = true
}

variable "network_firewall_enabled" {
  description = <<-EOT
    Reserviert fuer eine spaetere Inspection-VPC (zentrale AWS Network Firewall
    am Hub). In diesem Modul noch nicht implementiert, aber als Input akzeptiert,
    damit die spaetere Erweiterung das Modul-Interface nicht bricht.
  EOT
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Account-/Org-Kontext (kommt aus account-factory / organizations)
# ---------------------------------------------------------------------------

variable "management_account_id" {
  description = "Management-(Payer-)Account-ID. Nur zur Referenz/Tagging - der TGW lebt im Network-Account."
  type        = string
  default     = ""
}

variable "workload_account_ids" {
  description = <<-EOT
    Map Workload-Name => Account-ID (aus account-factory). Wird hier als
    OPTIONALE zusaetzliche RAM-Principal-Quelle gefuehrt, falls man den TGW
    nicht an die OU, sondern an einzelne Accounts teilen will. Primaerer
    Sharing-Weg bleibt die OU (siehe workloads_ou_arn).
  EOT
  type        = map(string)
  default     = {}
}

variable "vpc_ids" {
  description = <<-EOT
    Map VPC-Name => VPC-ID (aus dem vpc-Modul). Im Showcase nur informativ;
    die eigentlichen VPC-Attachments werden ueber var.vpc_attachments
    parametrisiert (inkl. Subnetzen), weil ein Attachment subnet_ids braucht.
  EOT
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Transit Gateway
# ---------------------------------------------------------------------------

variable "amazon_side_asn" {
  description = <<-EOT
    Private ASN der Amazon-Seite des TGW (BGP). Aus dem 16-bit privaten Bereich
    64512-65534 bzw. 32-bit 4200000000-4294967294. Muss eindeutig ggue. der
    on-prem ASN sein, sonst lehnt BGP die Session ab. Default 64512.
  EOT
  type        = number
  default     = 64512
  validation {
    condition = (
      (var.amazon_side_asn >= 64512 && var.amazon_side_asn <= 65534) ||
      (var.amazon_side_asn >= 4200000000 && var.amazon_side_asn <= 4294967294)
    )
    error_message = "amazon_side_asn muss im privaten ASN-Bereich 64512-65534 oder 4200000000-4294967294 liegen."
  }
}

variable "transit_gateway_route_tables" {
  description = <<-EOT
    Liste der TGW Route Tables fuer die Netzwerk-Segmentierung. NARA-Muster:
    - hub        : zentrale Dienste / Inspection / Shared Services
    - spoke-prod : Prod-Workloads (sehen Hub, NICHT spoke-dev)
    - spoke-dev  : Dev-Workloads  (sehen Hub, NICHT spoke-prod)
    - onprem     : VPN/DX-Attachment Richtung Rechenzentrum
    Getrennte Route Tables = Segmentierung ohne SecurityGroups/NACLs, rein ueber
    Routing. Das ist der Kern, warum wir die TGW-Defaults deaktivieren.
  EOT
  type        = list(string)
  default     = ["hub", "spoke-prod", "spoke-dev", "onprem"]
}

variable "vpc_attachments" {
  description = <<-EOT
    Parametrisierbare VPC-Attachments. Key = sprechender Name (z.B. "prod-app").
    - vpc_id / subnet_ids : ueblicherweise je AZ ein dediziertes /28 TGW-Subnet.
    - associated_route_table : GENAU EINE RT, die die Routing-Sicht dieses
      Attachments bestimmt (woHIN darf es?).
    - propagate_to : Liste der RTs, in die die CIDRs dieses Attachments
      propagiert werden (wer DARF ES erreichen?).
    Association != Propagation ist die zentrale NARA-Idee fuer Segmentierung.
  EOT
  type = map(object({
    vpc_id                 = string
    subnet_ids             = list(string)
    associated_route_table = string
    propagate_to           = list(string)
    appliance_mode         = optional(bool, false)
  }))
  default = {}
}

variable "transit_gateway_static_routes" {
  description = <<-EOT
    Statische TGW-Routen, z.B. Default-Route 0.0.0.0/0 in einer Spoke-RT auf das
    Hub/Inspection-Attachment, oder Blackhole-Routen zum gezielten Blocken.
    - blackhole=true => Traffic wird verworfen (attachment_key wird ignoriert).
  EOT
  type = map(object({
    route_table      = string
    destination_cidr = string
    attachment_key   = optional(string)
    blackhole        = optional(bool, false)
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# RAM (Resource Access Manager) - cross-account Sharing des TGW
# ---------------------------------------------------------------------------

variable "enable_ram_share" {
  description = "Erstellt den RAM Resource Share fuer den TGW (cross-account)."
  type        = bool
  default     = true
}

variable "workloads_ou_arn" {
  description = <<-EOT
    ARN der Workloads-OU (Format arn:aws:organizations::<mgmt-acct>:ou/o-xxx/ou-yyy).
    RAM-Principal: durch Sharing an die OU erbt JEDES aktuelle UND zukuenftige
    Account in der OU automatisch den TGW - kein Re-Share bei neuem Account
    (Account-Factory-freundlich). Leerer String => kein OU-Principal.
  EOT
  type        = string
  default     = ""
}

variable "enable_ram_organization_sharing" {
  description = <<-EOT
    Aktiviert "RAM sharing within AWS Organizations" (aws_ram_sharing_with_organization).
    Das ist ein EINMALIGER, org-weiter Schalter und wird in NARA normalerweise im
    Org-/Management-Baseline gesetzt, nicht pro Modul. Hier default=false, um
    Doppel-Management zu vermeiden; auf true setzen, wenn dieses Modul den
    Owner-Account verwaltet.
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = "Zusaetzliche Tags fuer alle Ressourcen."
  type        = map(string)
  default     = {}
}
