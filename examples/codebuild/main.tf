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
      Example   = "codebuild"
      ManagedBy = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "build" {
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "codebuild_logs" {
  name = "write-build-logs"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.build.arn}:*"
    }]
  })
}

resource "aws_codebuild_project" "this" {
  name                   = var.project_name
  description            = "2dollaraws CodeBuild learning project"
  service_role           = aws_iam_role.codebuild.arn
  build_timeout          = var.build_timeout_minutes
  queued_timeout         = 5
  concurrent_build_limit = 1
  badge_enabled          = false

  source {
    type      = "NO_SOURCE"
    buildspec = <<-EOT
      version: 0.2
      phases:
        install:
          commands:
            - echo install
        build:
          commands:
            - echo "hello from CodeBuild"
            - uname -m
            - cat /etc/os-release
            - nproc
            - free -m
        post_build:
          commands:
            - echo "done at $(date -u)"
    EOT
  }

  artifacts {
    type = "NO_ARTIFACTS"
  }

  cache {
    type = "NO_CACHE"
  }

  environment {
    compute_type                = var.compute_type
    type                        = var.environment_type
    image                       = var.image
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false
  }

  logs_config {
    cloudwatch_logs {
      status     = "ENABLED"
      group_name = aws_cloudwatch_log_group.build.name
    }
    s3_logs {
      status = "DISABLED"
    }
  }

  depends_on = [aws_iam_role_policy.codebuild_logs]
}

output "project_name" {
  value = aws_codebuild_project.this.name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.build.name
}

output "role_arn" {
  value = aws_iam_role.codebuild.arn
}
