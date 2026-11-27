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
      Example   = "daily-digest"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/handler.py"
  output_path = "${path.module}/build/daily-digest.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name}-summarize"
  retention_in_days = 7
}

resource "aws_iam_role" "lambda" {
  name = "${var.name}-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
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

resource "aws_iam_role_policy" "lambda_logs" {
  name = "${var.name}-lambda-logs"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
    }]
  })
}

resource "aws_lambda_function" "summarize" {
  function_name    = "${var.name}-summarize"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  memory_size      = 128
  timeout          = 15
  publish          = false

  environment {
    variables = {
      MIN_MAGNITUDE  = tostring(var.min_magnitude)
      TOP_N          = tostring(var.top_n)
      RETENTION_DAYS = tostring(var.retention_days)
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda_logs,
  ]
}

resource "aws_dynamodb_table" "days" {
  name                        = "${var.name}-days"
  billing_mode                = "PROVISIONED"
  read_capacity               = 1
  write_capacity              = 1
  hash_key                    = "report_date"
  deletion_protection_enabled = false

  attribute {
    name = "report_date"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = false
  }
}

resource "aws_sns_topic" "digest" {
  name = var.name
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.digest.arn
  protocol  = "email"
  endpoint  = var.alert_email
  # It stays PendingConfirmation until the email link is clicked. Terraform
  # cannot delete a pending subscription; AWS expires it after three days.
}

resource "aws_iam_role" "sfn" {
  name = "${var.name}-sfn"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
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

resource "aws_iam_role_policy" "sfn" {
  name = "${var.name}-sfn"
  role = aws_iam_role.sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.summarize.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem"]
        Resource = aws_dynamodb_table.days.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.digest.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "digest" {
  name     = var.name
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD"

  logging_configuration {
    level = "OFF"
  }

  tracing_configuration {
    enabled = false
  }

  definition = jsonencode({
    Comment = "Fetch yesterday's earthquakes, retain a short history, and email a digest."
    StartAt = "Summarize"
    States = {
      Summarize = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.summarize.arn
          "Payload.$"  = "$"
        }
        ResultSelector = {
          "report_date.$" = "$.Payload.report_date"
          "prev_date.$"   = "$.Payload.prev_date"
          "count.$"       = "$.Payload.count"
          "max_mag.$"     = "$.Payload.max_mag"
          "expires_at.$"  = "$.Payload.expires_at"
          "body.$"        = "$.Payload.body"
        }
        ResultPath     = "$.summary"
        TimeoutSeconds = 20
        Retry = [{
          ErrorEquals = [
            "Lambda.ServiceException",
            "Lambda.AWSLambdaException",
            "Lambda.SdkClientException",
            "Lambda.TooManyRequestsException",
            "States.TaskFailed",
          ]
          IntervalSeconds = 30
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = "NotifyFailure"
        }]
        Next = "GetPrevious"
      }
      GetPrevious = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:getItem"
        Parameters = {
          TableName = aws_dynamodb_table.days.name
          Key = {
            report_date = {
              "S.$" = "$.summary.prev_date"
            }
          }
          ProjectionExpression = "event_count"
        }
        ResultPath = "$.prev"
        Next       = "SaveToday"
      }
      SaveToday = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.days.name
          Item = {
            report_date = {
              "S.$" = "$.summary.report_date"
            }
            event_count = {
              "N.$" = "$.summary.count"
            }
            max_mag = {
              "N.$" = "$.summary.max_mag"
            }
            expires_at = {
              "N.$" = "$.summary.expires_at"
            }
          }
        }
        ResultPath = null
        Next       = "HasPrevious"
      }
      HasPrevious = {
        Type = "Choice"
        Choices = [{
          Variable  = "$.prev.Item"
          IsPresent = true
          Next      = "NotifyWithComparison"
        }]
        Default = "NotifyFirstDay"
      }
      NotifyWithComparison = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.digest.arn
          "Message.$" = "$.summary.body"
          "Subject.$" = "States.Format('Quake digest {}: {} events (prev day {})', $.summary.report_date, $.summary.count, $.prev.Item.event_count.N)"
        }
        ResultPath = null
        End        = true
      }
      NotifyFirstDay = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.digest.arn
          "Message.$" = "$.summary.body"
          "Subject.$" = "States.Format('Quake digest {}: {} events (no previous day stored)', $.summary.report_date, $.summary.count)"
        }
        ResultPath = null
        End        = true
      }
      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = aws_sns_topic.digest.arn
          Subject     = "Quake digest FAILED"
          "Message.$" = "$.error.Cause"
        }
        ResultPath = null
        Next       = "Failed"
      }
      Failed = {
        Type  = "Fail"
        Error = "DigestFailed"
      }
    }
  })

  depends_on = [aws_iam_role_policy.sfn]
}

resource "aws_iam_role" "scheduler" {
  name = "${var.name}-scheduler"

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
  name = "${var.name}-scheduler"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = aws_sfn_state_machine.digest.arn
    }]
  })
}

resource "aws_scheduler_schedule" "daily" {
  name                         = var.name
  group_name                   = "default"
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone
  state                        = var.schedule_state

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.digest.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})

    retry_policy {
      maximum_retry_attempts = 0
    }
  }

  depends_on = [aws_iam_role_policy.scheduler]
}
