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

locals {
  tags = {
    Example   = "cloudwatch-logs-alarm"
    ManagedBy = "Terraform"
  }
  namespace   = "TwoDollarAws/CloudWatchDemo"
  metric_name = "ErrorCount"
}

resource "aws_cloudwatch_log_group" "demo" {
  name              = "/zerobill/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  log_group_class   = "STANDARD" # Infrequent Access does not support metric filters.
  tags              = local.tags
}

# Log streams, metric filters and dashboards do not accept tags in the AWS provider.
resource "aws_cloudwatch_log_stream" "demo" {
  name           = "manual"
  log_group_name = aws_cloudwatch_log_group.demo.name
}

resource "aws_cloudwatch_log_metric_filter" "errors" {
  name           = "${var.name_prefix}-errors"
  log_group_name = aws_cloudwatch_log_group.demo.name
  pattern        = "\"ERROR\""

  # No dimensions: each dimension set would be a separate billable custom metric.
  metric_transformation {
    name          = local.metric_name
    namespace     = local.namespace
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# Standard resolution, plain metric, no actions: counts as 1 free alarm metric.
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${var.name_prefix}-errors"
  namespace           = local.namespace
  metric_name         = local.metric_name
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  tags                = local.tags

  depends_on = [aws_cloudwatch_log_metric_filter.errors]
}

resource "aws_cloudwatch_dashboard" "demo" {
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
          title   = "ErrorCount (Sum, 5 min)"
          region  = var.aws_region
          metrics = [[local.namespace, local.metric_name]]
          stat    = "Sum"
          period  = 300
          view    = "timeSeries"
        }
      },
      {
        type   = "alarm"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Error alarm"
          alarms = [aws_cloudwatch_metric_alarm.errors.arn]
        }
      }
    ]
  })
}
