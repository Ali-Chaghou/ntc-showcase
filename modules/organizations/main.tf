# modules/organizations/main.tf
# NTC-inspired Organizations - multi-account structure with OUs and policies

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "organization_name" {
  type = string
}

variable "enable_all_features" {
  type    = bool
  default = true
}

variable "organizational_units" {
  type = map(object({
    parent_id = optional(string)
    accounts  = optional(map(string))
  }))
}

variable "tags" {
  type    = map(string)
  default = {}
}

# Create AWS Organization
resource "aws_organizations_organization" "main" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "access-analyzer.amazonaws.com",
    "ram.amazonaws.com",
    "ec2.amazonaws.com",
    "rds.amazonaws.com"
  ]
  feature_set = var.enable_all_features ? "ALL" : "CONSOLIDATED_BILLING"
}

# Create root OU structure
resource "aws_organizations_organizational_unit" "root_ous" {
  for_each = var.organizational_units

  name      = each.key
  parent_id = each.value.parent_id != "" ? each.value.parent_id : aws_organizations_organization.main.roots[0].id
  tags      = var.tags
}

# Create nested OUs for workloads
resource "aws_organizations_organizational_unit" "workload_envs" {
  for_each = {
    for env in ["prod", "staging", "dev", "sandbox"] : env => env
  }

  name      = each.key
  parent_id = aws_organizations_organizational_unit.root_ous["workloads"].id
  tags      = merge(var.tags, { Environment = each.key })
}

# Organization-level policies (SCPs attached at root/OU level)
resource "aws_organizations_policy" "deny_root_access" {
  name        = "DenyRootUserAccess"
  description = "Prevents root user actions except for specific recovery scenarios"
  type        = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyRootUser"
      Effect    = "Deny"
      Principal = { AWS = "*" }
      Action    = ["*"]
      Resource  = "*"
      Condition = {
        StringLike = {
          "aws:PrincipalArn" = "arn:*:iam::*:root"
        }
      }
    }]
  })
}

resource "aws_organizations_policy" "require_mfa" {
  name        = "RequireMFAForConsole"
  description = "Enforces MFA for all console access"
  type        = "SERVICE_CONTROL_POLICY"
  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "RequireMFA"
      Effect = "Deny"
      NotAction = [
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:GetUser",
        "iam:ListMFADevices",
        "iam:ListVirtualMFADevices",
        "iam:ResyncMFADevice",
        "sts:GetSessionToken"
      ]
      Resource = "*"
      Condition = {
        BoolIfExists = { "aws:MultiFactorAuthPresent" = "false" }
      }
    }]
  })
}

# Attach SCPs to OUs
resource "aws_organizations_policy_attachment" "scp_attachments" {
  for_each = {
    for policy_name, policy in {
      "DenyRootUserAccess"   = aws_organizations_policy.deny_root_access
      "RequireMFAForConsole" = aws_organizations_policy.require_mfa
    } : policy_name => policy
  }

  policy_id = each.value.id
  target_id = aws_organizations_organization.main.roots[0].id
}

# Outputs
output "organization_id" {
  value = aws_organizations_organization.main.id
}

output "ou_ids" {
  value = {
    for k, v in aws_organizations_organizational_unit.root_ous : k => v.id
  }
}

output "workload_ou_ids" {
  value = {
    for k, v in aws_organizations_organizational_unit.workload_envs : k => v.id
  }
}