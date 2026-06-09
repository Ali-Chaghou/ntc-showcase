# modules/core-network/outputs.tf
# Wir nutzen one(...) statt [0], damit die Outputs auch sauber null liefern,
# wenn transit_gateway_enabled=false ist (count=0 -> leere Liste).

output "transit_gateway_id" {
  description = "ID des zentralen Transit Gateway (null wenn deaktiviert)."
  value       = one(aws_ec2_transit_gateway.this[*].id)
}

output "transit_gateway_arn" {
  description = "ARN des TGW - wird z.B. fuer RAM oder cross-account Referenzen gebraucht."
  value       = one(aws_ec2_transit_gateway.this[*].arn)
}

output "transit_gateway_association_default_route_table_id" {
  description = <<-EOT
    Default Association RT-ID des TGW. Bewusst nur informativ ausgegeben - wir
    benutzen sie NICHT (default association/propagation sind disabled), aber sie
    hilft beim Debuggen/Verstehen.
  EOT
  value       = one(aws_ec2_transit_gateway.this[*].association_default_route_table_id)
}

output "transit_gateway_route_table_ids" {
  description = "Map Segment-Name => TGW Route Table ID (hub/spoke-prod/spoke-dev/onprem)."
  value       = { for k, v in aws_ec2_transit_gateway_route_table.this : k => v.id }
}

output "vpc_attachment_ids" {
  description = "Map Attachment-Name => TGW VPC Attachment ID."
  value       = { for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => v.id }
}

output "ram_resource_share_arn" {
  description = "ARN des RAM Resource Share fuer den TGW (null wenn kein Sharing)."
  value       = one(aws_ram_resource_share.tgw[*].arn)
}
