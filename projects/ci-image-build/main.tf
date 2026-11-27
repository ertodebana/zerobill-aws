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
      Example   = "ci-image-build"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_ecrpublic_repository" "this" {
  repository_name = var.name
  force_destroy   = true

  catalog_data {
    description       = "zerobill CI image build learning project"
    about_text        = "Learning example. Safe to ignore."
    operating_systems = ["Linux"]
    architectures     = ["x86-64"]
  }
}

resource "aws_cloudwatch_log_group" "build" {
  name              = "/aws/codebuild/${var.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "codebuild" {
  name = "${var.name}-codebuild"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.name}-build-and-push"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BuildLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.build.arn}:*"
      },
      {
        Sid      = "EcrPublicToken"
        Effect   = "Allow"
        Action   = "ecr-public:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid      = "EcrPublicServiceBearerToken"
        Effect   = "Allow"
        Action   = "sts:GetServiceBearerToken"
        Resource = "*"
        Condition = {
          StringEquals = {
            "sts:AWSServiceName" = "ecr-public.amazonaws.com"
          }
        }
      },
      {
        Sid    = "PushToThisPublicRepository"
        Effect = "Allow"
        Action = [
          "ecr-public:BatchCheckLayerAvailability",
          "ecr-public:InitiateLayerUpload",
          "ecr-public:UploadLayerPart",
          "ecr-public:CompleteLayerUpload",
          "ecr-public:PutImage"
        ]
        Resource = aws_ecrpublic_repository.this.arn
      }
    ]
  })
}

resource "aws_codebuild_project" "this" {
  name                   = var.name
  service_role           = aws_iam_role.codebuild.arn
  build_timeout          = var.build_timeout_minutes
  queued_timeout         = 5
  concurrent_build_limit = 1
  badge_enabled          = false

  source {
    type      = "NO_SOURCE"
    buildspec = file("${path.module}/buildspec.yml")
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
    privileged_mode             = true

    environment_variable {
      name  = "REPO_URL"
      value = var.github_repo_url
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "GIT_REF"
      value = var.git_ref
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "DOCKERFILE"
      value = var.dockerfile_path
      type  = "PLAINTEXT"
    }

    environment_variable {
      name  = "IMAGE_URI"
      value = aws_ecrpublic_repository.this.repository_uri
      type  = "PLAINTEXT"
    }
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

  depends_on = [aws_iam_role_policy.codebuild]
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_cloudwatch_event_rule" "build_failed" {
  name = "${var.name}-failed"

  event_pattern = jsonencode({
    source        = ["aws.codebuild"]
    "detail-type" = ["CodeBuild Build State Change"]
    detail = {
      "project-name" = [var.name]
      "build-status" = ["FAILED", "TIMED_OUT"]
    }
  })
}

# This replaces the default SNS topic policy with an allow for only this rule.
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowOnlyThisBuildFailureRule"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.alerts.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = aws_cloudwatch_event_rule.build_failed.arn
        }
      }
    }]
  })
}

# The email subscription remains PendingConfirmation until its link is clicked.
# AWS expires an unconfirmed subscription after three days.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.build_failed.name
  target_id = "${var.name}-alerts"
  arn       = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      id      = "$.detail.build-id"
      project = "$.detail.project-name"
      status  = "$.detail.build-status"
      region  = "$.region"
    }

    input_template = "\"Build <id> of <project> ended with <status>. Logs: https://<region>.console.aws.amazon.com/codesuite/codebuild/projects/<project>/history\""
  }

  retry_policy {
    maximum_retry_attempts       = 0
    maximum_event_age_in_seconds = 3600
  }

  depends_on = [aws_sns_topic_policy.alerts]
}

resource "aws_iam_role" "scheduler" {
  count = var.schedule_expression == null ? 0 : 1
  name  = "${var.name}-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "scheduler.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.schedule_expression == null ? 0 : 1
  name  = "${var.name}-start-build"
  role  = aws_iam_role.scheduler[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "codebuild:StartBuild"
      Resource = aws_codebuild_project.this.arn
    }]
  })
}

resource "aws_scheduler_schedule" "weekly" {
  count = var.schedule_expression == null ? 0 : 1
  name  = "${var.name}-weekly"

  group_name                   = "default"
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:codebuild:startBuild"
    role_arn = aws_iam_role.scheduler[0].arn
    input    = jsonencode({ ProjectName = var.name })

    retry_policy {
      maximum_retry_attempts = 0
    }
  }

  depends_on = [aws_iam_role_policy.scheduler]
}
