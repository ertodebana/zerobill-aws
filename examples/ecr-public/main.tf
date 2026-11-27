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
      Example   = "ecr-public"
      ManagedBy = "Terraform"
    }
  }
}

# Everything pushed here is world-readable and listed in the ECR Public Gallery.
resource "aws_ecrpublic_repository" "this" {
  repository_name = var.repository_name
  force_destroy   = true

  catalog_data {
    description       = "zerobill ECR Public learning example (tiny busybox image)"
    about_text        = "Learning example. Safe to ignore."
    operating_systems = ["Linux"]
    architectures     = ["x86-64", "ARM 64"]
  }
}

output "repository_uri" {
  value = aws_ecrpublic_repository.this.repository_uri
}

output "repository_arn" {
  value = aws_ecrpublic_repository.this.arn
}

output "registry_id" {
  value = aws_ecrpublic_repository.this.registry_id
}
