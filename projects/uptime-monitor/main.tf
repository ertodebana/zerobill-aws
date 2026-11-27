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
      Example   = "uptime-monitor"
      ManagedBy = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  namespace  = "TwoDollarAws/Uptime"

  # cron fires at the start of each minute/5-minute boundary, so each run lands
  # inside exactly one alarm period. rate() starts from apply time and can drift
  # across a boundary, leaving an empty period, which counts as breaching.
  schedule_expression = var.check_interval_minutes == 1 ? "cron(* * * * ? *)" : "cron(0/5 * * * ? *)"

  url_map = { for i, u in var.urls : tostring(i) => u }
}

data "archive_file" "checker" {
  type        = "zip"
  source_file = "${path.module}/handler.py"
  output_path = "${path.module}/build/checker.zip"
}

# Lambda checker

resource "aws_cloudwatch_log_group" "checker" {
  name              = "/aws/lambda/${var.name_prefix}-checker"
  retention_in_days = 7
  log_group_class   = "STANDARD"
}

resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-checker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "checker"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.checker.arn}:*"
      },
      {
        # PutMetricData has no resource ARN; the namespace condition is the scoping.
        Effect    = "Allow"
        Action    = "cloudwatch:PutMetricData"
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = local.namespace } }
      },
      {
        Effect   = "Allow"
        Action   = "dynamodb:PutItem"
        Resource = aws_dynamodb_table.checks.arn
      }
    ]
  })
}

resource "aws_lambda_function" "checker" {
  function_name    = "${var.name_prefix}-checker"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  filename         = data.archive_file.checker.output_path
  source_code_hash = data.archive_file.checker.output_base64sha256
  memory_size      = 128
  timeout          = 20 # at most 3 URLs x 5 s each
  publish          = false

  environment {
    variables = {
      URLS       = jsonencode(var.urls)
      TABLE_NAME = aws_dynamodb_table.checks.name
      NAMESPACE  = local.namespace
      TTL_DAYS   = "7"
    }
  }

  depends_on = [aws_cloudwatch_log_group.checker, aws_iam_role_policy.lambda]
}

# One tick = one run: no async retries.
resource "aws_lambda_function_event_invoke_config" "checker" {
  function_name                = aws_lambda_function.checker.function_name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 60
}

# Raw history, 7-day TTL

# No server_side_encryption block: the AWS-owned key is used. enabled = true
# would switch to the AWS-managed KMS key, which makes KMS calls.
resource "aws_dynamodb_table" "checks" {
  name                        = "${var.name_prefix}-checks"
  billing_mode                = "PROVISIONED"
  read_capacity               = 1
  write_capacity              = 1
  hash_key                    = "url"
  range_key                   = "ts"
  table_class                 = "STANDARD"
  stream_enabled              = false
  deletion_protection_enabled = false

  attribute {
    name = "url"
    type = "S"
  }

  attribute {
    name = "ts"
    type = "N"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = false
  }
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
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name = "invoke-checker"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.checker.arn
    }]
  })
}

# Scheduler uses the role above, so no aws_lambda_permission is needed.
resource "aws_scheduler_schedule" "check" {
  name                         = "${var.name_prefix}-check"
  group_name                   = "default"
  schedule_expression          = local.schedule_expression
  schedule_expression_timezone = "UTC"
  state                        = var.schedule_state

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.checker.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ source = "uptime-monitor" })

    retry_policy {
      maximum_retry_attempts = 0
    }
  }

  depends_on = [aws_iam_role_policy.scheduler_invoke]
}

# Alerts

# Standard topic: no FIFO, no KMS, no delivery-status logging.
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
}

# Only this stack's alarms may publish. The deploying principal keeps access
# through its identity policy, because the topic is in the same account.
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.alerts.arn
      Condition = {
        ArnLike      = { "aws:SourceArn" = "arn:aws:cloudwatch:${var.aws_region}:${local.account_id}:alarm:${var.name_prefix}-*" }
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
}

# The subscription stays pending until you click the link in the email.
# Terraform can't delete a pending subscription; AWS expires it after 3 days, free.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# One standard-resolution alarm per URL. Missing data is breaching, so a broken
# checker or a paused schedule also alerts (dead-man's switch).
resource "aws_cloudwatch_metric_alarm" "down" {
  for_each = local.url_map

  alarm_name          = "${var.name_prefix}-down-${each.key}"
  alarm_description   = "DOWN: ${each.value}"
  namespace           = local.namespace
  metric_name         = "Up"
  dimensions          = { Url = each.value }
  statistic           = "Minimum"
  period              = var.check_interval_minutes * 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  depends_on = [aws_sns_topic_policy.alerts]
}

# No log or Logs Insights widgets: they scan logs.
resource "aws_cloudwatch_dashboard" "uptime" {
  dashboard_name = var.name_prefix

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Up (1 = up)"
          region  = var.aws_region
          metrics = [for u in var.urls : [local.namespace, "Up", "Url", u]]
          stat    = "Minimum"
          period  = var.check_interval_minutes * 60
          view    = "timeSeries"
          yAxis   = { left = { min = 0, max = 1 } }
        }
      },
      {
        type   = "alarm"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Down alarms"
          alarms = [for a in aws_cloudwatch_metric_alarm.down : a.arn]
        }
      }
    ]
  })
}
