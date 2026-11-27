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
}

# name_prefix, not name: a deprecated domain name can never be reused.
resource "aws_swf_domain" "this" {
  name_prefix                                 = var.domain_name_prefix
  description                                 = "2dollaraws SWF learning domain"
  workflow_execution_retention_period_in_days = tostring(var.retention_days)

  tags = {
    Example   = "swf-domain"
    ManagedBy = "Terraform"
  }
}

output "domain_name" {
  value = aws_swf_domain.this.name
}

output "domain_arn" {
  value = aws_swf_domain.this.arn
}
