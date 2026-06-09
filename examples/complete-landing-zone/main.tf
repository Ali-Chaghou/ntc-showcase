# NTC-Style Account Factory Module
# Purpose: Create and manage AWS accounts via Organizations with standardized baselines
# Inspired by: nuvibit/ntc-account-factory (proprietary)

module "account_factory" {
  source = "./modules/account-factory"

  organization_id      = module.organizations.organization_id
  ou_ids               = module.organizations.ou_ids
  management_email     = var.management_account_email
  audit_email          = var.audit_account_email
  log_archive_email    = var.log_archive_account_email
  workload_emails      = var.workload_account_emails
  organizational_units = var.organizational_units

  tags = merge(var.tags, {
    Module = "account-factory"
  })
}

module "organizations" {
  source = "./modules/organizations"

  organization_name    = var.organization_name
  enable_all_features  = true
  organizational_units = var.organizational_units

  tags = merge(var.tags, {
    Module = "organizations"
  })
}

module "core_network" {
  source = "./modules/core-network"

  transit_gateway_enabled  = var.transit_gateway_enabled
  network_firewall_enabled = var.network_firewall_enabled
  management_account_id    = data.aws_caller_identity.current.account_id
  workload_account_ids     = module.account_factory.workload_account_ids
  vpc_ids                  = module.vpc.vpc_ids

  tags = merge(var.tags, {
    Module = "core-network"
  })
}

module "vpc" {
  source = "./modules/vpc"

  workload_account_ids = module.account_factory.workload_account_ids
  ipam_pool_ids        = var.ipam_enabled ? module.ipam.pool_ids : {}
  cidr_blocks          = var.vpc_cidr_blocks

  tags = merge(var.tags, {
    Module = "vpc"
  })
}

module "identity_center" {
  source = "./modules/identity-center"

  enabled               = var.identity_center_enabled
  management_account_id = data.aws_caller_identity.current.account_id
  workload_account_ids  = module.account_factory.workload_account_ids
  permission_sets       = local.permission_sets

  tags = merge(var.tags, {
    Module = "identity-center"
  })
}

module "security_tooling" {
  source = "./modules/security-tooling"

  enable_guardrails       = var.enable_guardrails
  management_account_id   = data.aws_caller_identity.current.account_id
  audit_account_id        = module.account_factory.account_ids["audit"]
  log_archive_account_id  = module.account_factory.account_ids["log-archive"]
  workload_account_ids    = module.account_factory.workload_account_ids
  organizational_unit_ids = module.organizations.ou_ids

  tags = merge(var.tags, {
    Module = "security-tooling"
  })
}

module "log_archive" {
  source = "./modules/log-archive"

  enable_central_logging  = var.enable_central_logging
  management_account_id   = data.aws_caller_identity.current.account_id
  audit_account_id        = module.account_factory.account_ids["audit"]
  log_archive_account_id  = module.account_factory.account_ids["log-archive"]
  workload_account_ids    = module.account_factory.workload_account_ids
  organizational_unit_ids = module.organizations.ou_ids

  tags = merge(var.tags, {
    Module = "log-archive"
  })
}

module "guardrails" {
  source = "./modules/guardrails"

  enable_guardrails       = var.enable_guardrails
  management_account_id   = data.aws_caller_identity.current.account_id
  audit_account_id        = module.account_factory.account_ids["audit"]
  organizational_unit_ids = module.organizations.ou_ids

  tags = merge(var.tags, {
    Module = "guardrails"
  })
}

module "ipam" {
  source = "./modules/ipam"

  enabled               = var.ipam_enabled
  management_account_id = data.aws_caller_identity.current.account_id
  operating_regions     = ["eu-central-1", "eu-west-1"]

  tags = merge(var.tags, {
    Module = "ipam"
  })
}

module "route53" {
  source = "./modules/route53"

  hosted_zones = var.route53_hosted_zones
  vpc_ids      = module.vpc.vpc_ids

  tags = merge(var.tags, {
    Module = "route53"
  })
}

module "parameters" {
  source = "./modules/parameters"

  management_account_id = data.aws_caller_identity.current.account_id
  workload_account_ids  = module.account_factory.workload_account_ids

  tags = merge(var.tags, {
    Module = "parameters"
  })
}

locals {
  permission_sets = {
    "AWSAdministratorAccess" = {
      description      = "Full administrator access"
      session_duration = "PT8H"
      relay_state      = "https://console.aws.amazon.com/"
      inline_policy    = data.aws_iam_policy_document.admin.json
      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }
    "PowerUserAccess" = {
      description      = "Power user access (no IAM/Org management)"
      session_duration = "PT8H"
      relay_state      = "https://console.aws.amazon.com/"
      managed_policies = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    }
    "ReadOnlyAccess" = {
      description      = "Read-only access"
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
    "SecurityAudit" = {
      description      = "Security audit access"
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/SecurityAudit"]
    }
  }
}

data "aws_iam_policy_document" "admin" {
  statement {
    sid       = "AllowAll"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }
}