terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # aws_dsql_cluster first shipped in 5.100.0.
      version = "~> 5.100"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Example   = "aurora-dsql-cluster"
      ManagedBy = "Terraform"
    }
  }
}

resource "aws_dsql_cluster" "this" {
  deletion_protection_enabled = false
  kms_encryption_key          = "AWS_OWNED_KMS_KEY"

  tags = {
    Name    = var.cluster_name
    Project = "zerobill"
  }
}
