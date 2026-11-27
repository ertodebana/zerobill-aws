terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
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
      Example   = "webhook-ingest-queue"
      ManagedBy = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

data "archive_file" "ingest" {
  type        = "zip"
  source_file = "${path.module}/ingest.py"
  output_path = "${path.module}/ingest.zip"
}

data "archive_file" "worker" {
  type        = "zip"
  source_file = "${path.module}/worker.py"
  output_path = "${path.module}/worker.zip"
}

# The real secret is written out of band so it never enters Terraform state.
resource "aws_ssm_parameter" "secret" {
  name        = "/${var.name}/webhook-secret"
  description = "HMAC secret for the ${var.name} demo; set the real value out of band."
  type        = "SecureString"
  tier        = "Standard"
  value       = "REPLACE_ME"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 345600
  sqs_managed_sse_enabled   = true
  max_message_size          = 65536
  receive_wait_time_seconds = 20
}

resource "aws_sqs_queue" "main" {
  name                       = var.name
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 60
  receive_wait_time_seconds  = 20
  max_message_size           = 65536
  delay_seconds              = 0
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}

resource "aws_dynamodb_table" "events" {
  name                        = "${var.name}-events"
  billing_mode                = "PROVISIONED"
  read_capacity               = var.table_read_capacity
  write_capacity              = var.table_write_capacity
  hash_key                    = "event_id"
  stream_enabled              = false
  deletion_protection_enabled = false
  table_class                 = "STANDARD"

  attribute {
    name = "event_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = false
  }

  # Omit server_side_encryption: this project uses DynamoDB's free AWS-owned key.
  # examples/dynamodb-provisioned enables the AWS-managed key, which adds KMS requests.
}

resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${var.name}-ingest"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/aws/lambda/${var.name}-worker"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "ingest" {
  name = "${var.name}-ingest-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ingest" {
  name = "${var.name}-ingest-inline"
  role = aws_iam_role.ingest.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.ingest.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.main.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.secret.arn
      }
    ]
  })
}

resource "aws_iam_role" "worker" {
  name = "${var.name}-worker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "worker" {
  name = "${var.name}-worker-inline"
  role = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.worker.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.main.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.events.arn
      }
    ]
  })
}

resource "aws_lambda_function" "ingest" {
  function_name    = "${var.name}-ingest"
  role             = aws_iam_role.ingest.arn
  handler          = "ingest.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.ingest.output_path
  source_code_hash = data.archive_file.ingest.output_base64sha256
  memory_size      = 128
  timeout          = 3
  publish          = false

  reserved_concurrent_executions = var.ingest_reserved_concurrency == null ? -1 : var.ingest_reserved_concurrency

  environment {
    variables = {
      QUEUE_URL         = aws_sqs_queue.main.id
      SECRET_PARAM      = aws_ssm_parameter.secret.name
      MAX_BODY_BYTES    = tostring(var.max_body_bytes)
      TOLERANCE_SECONDS = tostring(var.signature_tolerance_seconds)
      PLACEHOLDER       = "REPLACE_ME"
    }
  }

  depends_on = [aws_iam_role_policy.ingest, aws_cloudwatch_log_group.ingest]
}

resource "aws_lambda_function_url" "ingest" {
  function_name      = aws_lambda_function.ingest.function_name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"
}

# The second permission is conditional on Function URL invocation; provider 6.28.0
# is the first release that can express invoked_via_function_url safely.
resource "aws_lambda_permission" "url_invoke_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.ingest.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "url_invoke_function" {
  statement_id             = "AllowPublicFunctionUrlInvoke"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.ingest.function_name
  principal                = "*"
  invoked_via_function_url = true

  depends_on = [aws_lambda_function_url.ingest]
}

resource "aws_lambda_function" "worker" {
  function_name    = "${var.name}-worker"
  role             = aws_iam_role.worker.arn
  handler          = "worker.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.worker.output_path
  source_code_hash = data.archive_file.worker.output_base64sha256
  memory_size      = 128
  timeout          = 10
  publish          = false

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.events.name
      TTL_DAYS   = tostring(var.dedup_ttl_days)
    }
  }

  depends_on = [aws_iam_role_policy.worker, aws_cloudwatch_log_group.worker]
}

resource "aws_lambda_event_source_mapping" "worker" {
  event_source_arn                   = aws_sqs_queue.main.arn
  function_name                      = aws_lambda_function.worker.arn
  enabled                            = var.worker_enabled
  batch_size                         = 10
  maximum_batching_window_in_seconds = 0
  function_response_types            = ["ReportBatchItemFailures"]

  # No scaling_config: preserve Lambda's low-traffic two-poller optimization.
  # No provisioned_poller_config: provisioned polling is billed by EPU-hour.
  # No filter_criteria: the worker deliberately demonstrates poison-message handling.
  # No metrics_config: AWS-vended SQS metrics are enough for this learning dashboard.
  depends_on = [aws_iam_role_policy.worker]
}

resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

# A pending email confirmation cannot be deleted by Terraform; AWS expires it after 3 days at no cost.
resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.name}-dlq-depth"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 18
        height = 6
        properties = {
          title  = "Empty receives = idle poller cost"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", aws_sqs_queue.main.name],
            ["AWS/SQS", "NumberOfMessagesReceived", "QueueName", aws_sqs_queue.main.name],
            ["AWS/SQS", "NumberOfEmptyReceives", "QueueName", aws_sqs_queue.main.name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 18
        height = 6
        properties = {
          title  = "Visible messages: main queue and DLQ"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Maximum"
          period = 60
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.main.name],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.dlq.name]
          ]
        }
      },
      {
        type   = "alarm"
        x      = 18
        y      = 0
        width  = 6
        height = 6
        properties = {
          title  = "DLQ alarm"
          alarms = [aws_cloudwatch_metric_alarm.dlq_depth.arn]
        }
      }
    ]
  })
}
