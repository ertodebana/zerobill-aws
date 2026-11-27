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
      Example   = "managed-prometheus"
      ManagedBy = "Terraform"
    }
  }
}

resource "aws_prometheus_workspace" "demo" {
  alias = var.name_prefix

  # AWS-owned encryption key (no kms_key_arn) and no vended logging, to avoid extra charges.
  tags = {
    Project = "2dollaraws"
  }
}

# Lower retention from the 150-day service default.
# aws_prometheus_workspace_configuration has no tags argument, so default_tags do not reach it.
resource "aws_prometheus_workspace_configuration" "demo" {
  workspace_id             = aws_prometheus_workspace.demo.id
  retention_period_in_days = var.retention_days
}

# Not attached by Terraform. Attach it to the user or role you run the demo as.
resource "aws_iam_policy" "amp_demo" {
  name        = "${var.name_prefix}-remote-write-query"
  description = "Remote write and query access to the ${var.name_prefix} AMP workspace only."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "aps:RemoteWrite",
        "aps:QueryMetrics",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata",
      ]
      Resource = aws_prometheus_workspace.demo.arn
    }]
  })
}
