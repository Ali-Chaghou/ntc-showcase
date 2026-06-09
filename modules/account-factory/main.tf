# modules/account-factory/main.tf
# NTC-inspired Account Factory - creates AWS accounts with standardized baselines

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "organization_id" {
  type = string
}

variable "ou_ids" {
  type = map(string)
}

variable "management_email" {
  type      = string
  sensitive = true
}

variable "audit_email" {
  type      = string
  sensitive = true
}

variable "log_archive_email" {
  type      = string
  sensitive = true
}

variable "workload_emails" {
  type = map(string)
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

# Create audit account
resource "aws_organizations_account" "audit" {
  name      = "Audit"
  email     = var.audit_email
  parent_id = var.ou_ids["security"]
  tags      = merge(var.tags, { AccountType = "audit" })
}

# Create log-archive account
resource "aws_organizations_account" "log_archive" {
  name      = "Log-Archive"
  email     = var.log_archive_email
  parent_id = var.ou_ids["security"]
  tags      = merge(var.tags, { AccountType = "log-archive" })
}

# Create workload accounts
resource "aws_organizations_account" "workload" {
  for_each = var.workload_emails

  name      = each.key
  email     = each.value
  parent_id = var.ou_ids["workloads"]
  tags      = merge(var.tags, { AccountType = "workload", WorkloadEnv = each.key })
}

# Wait for account creation (Organizations eventual consistency)
resource "time_sleep" "wait_for_accounts" {
  depends_on = [
    aws_organizations_account.audit,
    aws_organizations_account.log_archive,
    aws_organizations_account.workload
  ]
  create_duration = "60s"
}

# Account baseline role for cross-account access
resource "aws_iam_role" "account_baseline" {
  for_each = aws_organizations_account.workload

  name = "OrganizationAccountAccessRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "ntc-account-factory-${var.organization_id}"
        }
      }
    }]
  })
  tags = merge(var.tags, { AccountType = "workload", WorkloadEnv = each.key })
}

# Outputs
output "account_ids" {
  value = {
    "audit"       = aws_organizations_account.audit.id
    "log-archive" = aws_organizations_account.log_archive.id
  }
}

output "workload_account_ids" {
  value = { for k, v in aws_organizations_account.workload : k => v.id }
}