terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Example   = "ssm-parameter-store"
      ManagedBy = "Terraform"
    }
  }
}

resource "aws_ssm_parameter" "log_level" {
  name        = "${var.prefix}/log-level"
  type        = "String"
  tier        = "Standard"
  data_type   = "text"
  value       = "info"
  description = "Demo log level"
}

# No key_id: encrypted with the AWS-managed key alias/aws/ssm (no monthly key fee).
# The value is stored in plaintext in terraform.tfstate. Dummy values only.
resource "aws_ssm_parameter" "db_password" {
  name        = "${var.prefix}/db-password"
  type        = "SecureString"
  tier        = "Standard"
  value       = var.db_password
  description = "Demo secret, dummy value"
}
