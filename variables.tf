variable "aws_region" {
  description = "Primary AWS region for the landing zone"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (management, audit, log-archive, prod, staging, dev)"
  type        = string
  validation {
    condition     = contains(["management", "audit", "log-archive", "prod", "staging", "dev"], var.environment)
    error_message = "Environment must be one of: management, audit, log-archive, prod, staging, dev"
  }
}

variable "organization_name" {
  description = "Organization name for AWS Organizations"
  type        = string
  default     = "ntc-showcase-org"
}

variable "management_account_email" {
  description = "Email for the management account (root)"
  type        = string
  sensitive   = true
}

variable "audit_account_email" {
  description = "Email for the audit account"
  type        = string
  sensitive   = true
}

variable "log_archive_account_email" {
  description = "Email for the log archive account"
  type        = string
  sensitive   = true
}

variable "workload_account_emails" {
  description = "Map of workload account names to emails"
  type        = map(string)
  default = {
    "prod"    = "prod@company.ch"
    "staging" = "staging@company.ch"
    "dev"     = "dev@company.ch"
  }
}

variable "organizational_units" {
  description = "OU structure for AWS Organizations"
  type = map(object({
    parent_id = optional(string)
    accounts  = optional(map(string))
  }))
  default = {
    "security" = {
      accounts = {
        "audit"       = "audit@company.ch"
        "log-archive" = "log-archive@company.ch"
      }
    }
    "workloads" = {
      accounts = {
        "prod"    = "prod@company.ch"
        "staging" = "staging@company.ch"
        "dev"     = "dev@company.ch"
      }
    }
    "sandbox" = {
      accounts = {}
    }
  }
}

variable "enable_guardrails" {
  description = "Enable preventive and detective guardrails (SCPs, Config Rules)"
  type        = bool
  default     = true
}

variable "enable_central_logging" {
  description = "Enable centralized CloudTrail and Config logging"
  type        = bool
  default     = true
}

variable "identity_center_enabled" {
  description = "Enable AWS IAM Identity Center (SSO)"
  type        = bool
  default     = true
}

variable "transit_gateway_enabled" {
  description = "Enable Transit Gateway for core network"
  type        = bool
  default     = true
}

variable "network_firewall_enabled" {
  description = "Enable AWS Network Firewall for inspection"
  type        = bool
  default     = true
}

variable "ipam_enabled" {
  description = "Enable VPC IP Address Manager (IPAM)"
  type        = bool
  default     = true
}

variable "route53_hosted_zones" {
  description = "Private hosted zones to create"
  type = map(object({
    vpc_ids = list(string)
  }))
  default = {}
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}