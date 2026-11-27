terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Example   = "eventbridge"
      ManagedBy = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

data "archive_file" "function" {
  type        = "zip"
  source_file = "${path.module}/handler.py"
  output_path = "${path.module}/function.zip"
}

# Lambda target

resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "target" {
  name              = "/aws/lambda/${var.name_prefix}-target"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "logs" {
  name = "write-function-logs"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.target.arn}:*"
    }]
  })
}

resource "aws_lambda_function" "target" {
  function_name    = "${var.name_prefix}-target"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.function.output_path
  source_code_hash = data.archive_file.function.output_base64sha256
  memory_size      = 128
  timeout          = 3
  publish          = false
  depends_on       = [aws_iam_role_policy.logs, aws_cloudwatch_log_group.target]
}

# Scheduler

resource "aws_iam_role" "scheduler" {
  name = "${var.name_prefix}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "invoke" {
  name = "invoke-target"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.target.arn
    }]
  })
}

# Scheduler uses the role above, so no aws_lambda_permission is needed.
resource "aws_scheduler_schedule" "tick" {
  name                = "${var.name_prefix}-tick"
  group_name          = "default"
  schedule_expression = var.schedule_expression
  state               = var.schedule_state

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.target.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ source = "eventbridge-scheduler-demo" })

    retry_policy {
      maximum_retry_attempts = 0
    }
  }

  depends_on = [aws_iam_role_policy.invoke]
}
