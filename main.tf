terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "ntc-showcase-terraform-state"
    key            = "landing-zone/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "ntc-showcase-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "ntc-showcase"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "cloud-platform-team"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project     = "ntc-showcase"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "cloud-platform-team"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}