output "organization_id" {
  description = "AWS Organizations ID"
  value       = module.organizations.organization_id
}

output "management_account_id" {
  description = "Management (payer) account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "audit_account_id" {
  description = "Audit account ID"
  value       = module.account_factory.account_ids["audit"]
}

output "log_archive_account_id" {
  description = "Log archive account ID"
  value       = module.account_factory.account_ids["log-archive"]
}

output "workload_account_ids" {
  description = "Map of workload account names to IDs"
  value       = module.account_factory.workload_account_ids
}

output "organizational_unit_ids" {
  description = "Map of OU names to IDs"
  value       = module.organizations.ou_ids
}

output "transit_gateway_id" {
  description = "Transit Gateway ID (if enabled)"
  value       = module.core_network.transit_gateway_id
}

output "vpc_ids" {
  description = "Map of VPC names to IDs per account/region"
  value       = module.vpc.vpc_ids
}

output "identity_center_arn" {
  description = "IAM Identity Center instance ARN (if enabled)"
  value       = module.identity_center.instance_arn
}

output "guardrail_policy_ids" {
  description = "SCP and Config Rule IDs for guardrails"
  value       = module.guardrails.policy_ids
}

output "log_archive_bucket_arn" {
  description = "Central log archive S3 bucket ARN"
  value       = module.log_archive.bucket_arn
}

output "ipam_pool_ids" {
  description = "IPAM pool IDs (if enabled)"
  value       = module.ipam.pool_ids
}

output "route53_zone_ids" {
  description = "Route53 private hosted zone IDs"
  value       = module.route53.zone_ids
}