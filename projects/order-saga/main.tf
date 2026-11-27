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
      Example   = "order-saga"
      ManagedBy = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  skus = {
    "SKU-RED"  = 10
    "SKU-BLUE" = 10
    "SKU-LAST" = 1
  }

  # Predictable ARN avoids a role-policy/state-machine dependency cycle.
  state_machine_arn = "arn:${data.aws_partition.current.partition}:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.name}"
}

resource "aws_dynamodb_table" "orders" {
  name         = "${var.name}-orders"
  billing_mode = "PROVISIONED"
  hash_key     = "orderId"

  read_capacity  = 1
  write_capacity = 2
  table_class    = "STANDARD"

  attribute {
    name = "orderId"
    type = "S"
  }

  ttl {
    attribute_name = "expiresAt"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = false
  }

  stream_enabled = false

  # DynamoDB always encrypts at rest. Leaving SSE disabled uses the AWS-owned key.
  server_side_encryption {
    enabled = false
  }
}

resource "aws_dynamodb_table" "inventory" {
  name         = "${var.name}-inventory"
  billing_mode = "PROVISIONED"
  hash_key     = "sku"

  read_capacity  = 1
  write_capacity = 2
  table_class    = "STANDARD"

  attribute {
    name = "sku"
    type = "S"
  }

  point_in_time_recovery {
    enabled = false
  }

  stream_enabled = false

  # DynamoDB always encrypts at rest. Leaving SSE disabled uses the AWS-owned key.
  server_side_encryption {
    enabled = false
  }
}

resource "aws_dynamodb_table_item" "seed" {
  for_each   = local.skus
  table_name = aws_dynamodb_table.inventory.name
  hash_key   = aws_dynamodb_table.inventory.hash_key
  item = jsonencode({
    sku       = { S = each.key }
    available = { N = tostring(each.value) }
  })

  # The saga mutates stock. Terraform must not reset it on the next apply.
  lifecycle {
    ignore_changes = [item]
  }
}

resource "aws_sns_topic" "notifications" {
  name = "${var.name}-notifications"
}

# Terraform cannot delete a pending email subscription. AWS expires it after 3 days; it costs nothing.
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

data "archive_file" "place_order" {
  type        = "zip"
  source_file = "${path.module}/src/place_order.py"
  output_path = "${path.module}/place_order.zip"
}

data "archive_file" "payment" {
  type        = "zip"
  source_file = "${path.module}/src/payment.py"
  output_path = "${path.module}/payment.zip"
}

resource "aws_cloudwatch_log_group" "place_order" {
  name              = "/aws/lambda/${var.name}-place-order"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "payment" {
  name              = "/aws/lambda/${var.name}-payment"
  retention_in_days = 7
}

resource "aws_iam_role" "place_order" {
  name = "${var.name}-place-order"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role" "payment" {
  name = "${var.name}-payment"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role" "sfn" {
  name = "${var.name}-sfn"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "place_order" {
  name = "${var.name}-place-order"
  role = aws_iam_role.place_order.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.place_order.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = local.state_machine_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "payment" {
  name = "${var.name}-payment-logs"
  role = aws_iam_role.payment.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.payment.arn}:*"
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
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.orders.arn
      },
      {
        Effect   = "Allow"
        Action   = "dynamodb:UpdateItem"
        Resource = aws_dynamodb_table.inventory.arn
      },
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [aws_lambda_function.payment.arn, "${aws_lambda_function.payment.arn}:*"]
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.notifications.arn
      }
    ]
  })
}

resource "aws_lambda_function" "payment" {
  function_name    = "${var.name}-payment"
  role             = aws_iam_role.payment.arn
  handler          = "payment.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.payment.output_path
  source_code_hash = data.archive_file.payment.output_base64sha256
  memory_size      = 128
  timeout          = 3
  publish          = false

  depends_on = [aws_iam_role_policy.payment, aws_cloudwatch_log_group.payment]
}

resource "aws_lambda_function" "place_order" {
  function_name    = "${var.name}-place-order"
  role             = aws_iam_role.place_order.arn
  handler          = "place_order.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.place_order.output_path
  source_code_hash = data.archive_file.place_order.output_base64sha256
  memory_size      = 128
  timeout          = 3
  publish          = false

  reserved_concurrent_executions = var.place_order_reserved_concurrency

  environment {
    variables = {
      STATE_MACHINE_ARN = local.state_machine_arn
      ORDER_TTL_DAYS    = tostring(var.order_ttl_days)
    }
  }

  depends_on = [aws_iam_role_policy.place_order, aws_cloudwatch_log_group.place_order]
}

resource "aws_lambda_function_url" "place_order" {
  function_name      = aws_lambda_function.place_order.function_name
  authorization_type = var.function_url_auth_type
}

# URLs created with Terraform need both statements when public. The second action
# is restricted to calls made through the function URL.
resource "aws_lambda_permission" "url_invoke" {
  count                  = var.function_url_auth_type == "NONE" ? 1 : 0
  statement_id           = "AllowFunctionUrlInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.place_order.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "url_function_invoke" {
  count                  = var.function_url_auth_type == "NONE" ? 1 : 0
  statement_id           = "AllowFunctionUrlFunctionInvoke"
  action                 = "lambda:InvokeFunction"
  function_name          = aws_lambda_function.place_order.function_name
  principal              = "*"
  invoked_via_function_url = true
}

resource "aws_sfn_state_machine" "saga" {
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
    Comment        = "Order saga with stock reservation and compensation."
    TimeoutSeconds = 60
    StartAt        = "CreateOrder"
    States = {
      CreateOrder = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:putItem"
        Parameters = {
          TableName = aws_dynamodb_table.orders.name
          Item = {
            orderId     = { "S.$" = "$.orderId" }
            sku         = { "S.$" = "$.sku" }
            qty         = { "N.$" = "$.qty" }
            amountCents = { "N.$" = "States.Format('{}', $.amountCents)" }
            status      = { S = "PENDING" }
            stockState  = { S = "NONE" }
            simulate    = { "S.$" = "$.simulate" }
            createdAt   = { "S.$" = "$$.State.EnteredTime" }
            expiresAt   = { "N.$" = "$.expiresAt" }
          }
          ConditionExpression = "attribute_not_exists(orderId)"
        }
        ResultPath = null
        Catch = [{
          ErrorEquals = ["DynamoDB.ConditionalCheckFailedException"]
          Next        = "DuplicateOrder"
        }]
        Next = "ReserveStock"
      }
      ReserveStock = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:dynamodb:transactWriteItems"
        Parameters = {
          TransactItems = [
            { Update = {
              TableName = aws_dynamodb_table.inventory.name
              Key       = { sku = { "S.$" = "$.sku" } }
              UpdateExpression    = "SET #a = #a - :q"
              ConditionExpression = "#a >= :q"
              ExpressionAttributeNames = { "#a" = "available" }
              ExpressionAttributeValues = {
                ":q" = { "N.$" = "$.qty" }
              }
            } },
            { Update = {
              TableName = aws_dynamodb_table.orders.name
              Key       = { orderId = { "S.$" = "$.orderId" } }
              UpdateExpression    = "SET #stockState = :reserved"
              ConditionExpression = "#stockState = :none"
              ExpressionAttributeNames = { "#stockState" = "stockState" }
              ExpressionAttributeValues = {
                ":reserved" = { S = "RESERVED" }
                ":none"     = { S = "NONE" }
              }
            } }
          ]
        }
        ResultPath = null
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 1
          MaxAttempts      = 2
          BackoffRate      = 2
        }]
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "MarkCancelled" }]
        Next  = "ChargePayment"
      }
      ChargePayment = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        TimeoutSeconds = 10
        Parameters = {
          FunctionName = aws_lambda_function.payment.arn
          Payload = {
            action = "charge"
            "orderId.$" = "$.orderId"
            "amountCents.$" = "$.amountCents"
            "simulate.$" = "$.simulate"
          }
        }
        ResultSelector = { "paymentId.$" = "$.Payload.paymentId" }
        ResultPath     = "$.payment"
        Retry = [{
          ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 1
          MaxAttempts      = 2
          BackoffRate      = 2
        }]
        Catch = [
          { ErrorEquals = ["PaymentDeclined"], ResultPath = "$.error", Next = "ReleaseStock" },
          { ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "ReleaseStock" }
        ]
        Next = "ConfirmOrder"
      }
      ConfirmOrder = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.orders.name
          Key       = { orderId = { "S.$" = "$.orderId" } }
          UpdateExpression    = "SET #s = :confirmed, paymentId = :p"
          ConditionExpression = "#s = :pending AND #simulate <> :fail"
          ExpressionAttributeNames = { "#s" = "status", "#simulate" = "simulate" }
          ExpressionAttributeValues = {
            ":confirmed" = { S = "CONFIRMED" }
            ":pending"   = { S = "PENDING" }
            ":p"         = { "S.$" = "$.payment.paymentId" }
            ":fail"      = { S = "fail_after_charge" }
          }
        }
        ResultPath = null
        Catch = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "RefundPayment" }]
        Next  = "NotifyConfirmed"
      }
      NotifyConfirmed = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.notifications.arn
          "Message.$" = "States.Format('Order {} confirmed: {} x {}', $.orderId, $.qty, $.sku)"
          "Subject.$" = "States.Format('Order {} confirmed', $.orderId)"
        }
        ResultPath = null
        Retry = [{
          ErrorEquals = ["States.TaskFailed"]
          IntervalSeconds = 1
          MaxAttempts      = 2
          BackoffRate      = 2
        }]
        # No Catch: a failed notification must not undo a confirmed order.
        Next = "OrderConfirmed"
      }
      OrderConfirmed = { Type = "Succeed" }
      DuplicateOrder = {
        Type  = "Fail"
        Error = "DuplicateOrder"
        Cause = "This orderId already exists. Use a new id for another order."
      }
      RefundPayment = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        TimeoutSeconds = 10
        Parameters = {
          FunctionName = aws_lambda_function.payment.arn
          Payload = {
            action = "refund"
            "orderId.$" = "$.orderId"
            "paymentId.$" = "$.payment.paymentId"
          }
        }
        ResultSelector = { "refundId.$" = "$.Payload.refundId" }
        ResultPath     = "$.refund"
        Retry = [{
          ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 1
          MaxAttempts      = 2
          BackoffRate      = 2
        }]
        # No Catch: if refunding fails, the execution must surface that failure.
        Next = "ReleaseStock"
      }
      ReleaseStock = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:dynamodb:transactWriteItems"
        Parameters = {
          TransactItems = [
            { Update = {
              TableName = aws_dynamodb_table.inventory.name
              Key       = { sku = { "S.$" = "$.sku" } }
              UpdateExpression = "SET #a = #a + :q"
              ExpressionAttributeNames = { "#a" = "available" }
              ExpressionAttributeValues = { ":q" = { "N.$" = "$.qty" } }
            } },
            { Update = {
              TableName = aws_dynamodb_table.orders.name
              Key       = { orderId = { "S.$" = "$.orderId" } }
              UpdateExpression    = "SET #stockState = :released"
              ConditionExpression = "#stockState = :reserved"
              ExpressionAttributeNames = { "#stockState" = "stockState" }
              ExpressionAttributeValues = {
                ":released" = { S = "RELEASED" }
                ":reserved" = { S = "RESERVED" }
              }
            } }
          ]
        }
        ResultPath = null
        Retry = [{
          ErrorEquals = ["States.TaskFailed"]
          IntervalSeconds = 1
          MaxAttempts      = 2
          BackoffRate      = 2
        }]
        # No Catch: a failed compensation must surface in the execution history.
        # ponytail: a retry after a lost-but-successful response trips the stockState guard and fails the execution with data correct; add a Choice on CancellationReasons if that matters.
        Next = "MarkCancelled"
      }
      MarkCancelled = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.orders.name
          Key       = { orderId = { "S.$" = "$.orderId" } }
          UpdateExpression    = "SET #s = :cancelled, #r = :reason"
          ConditionExpression = "#s = :pending"
          ExpressionAttributeNames = { "#s" = "status", "#r" = "reason" }
          ExpressionAttributeValues = {
            ":cancelled" = { S = "CANCELLED" }
            ":pending"   = { S = "PENDING" }
            ":reason"    = { "S.$" = "$.error.Error" }
          }
        }
        ResultPath = null
        Next       = "NotifyCancelled"
      }
      NotifyCancelled = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = aws_sns_topic.notifications.arn
          "Message.$" = "States.Format('Order {} cancelled: {} x {}. Reason: {}', $.orderId, $.qty, $.sku, $.error.Error)"
          "Subject.$" = "States.Format('Order {} cancelled', $.orderId)"
        }
        ResultPath = null
        Retry = [{
          ErrorEquals = ["States.TaskFailed"]
          IntervalSeconds = 1
          MaxAttempts      = 2
          BackoffRate      = 2
        }]
        # No Catch: keep a notification error visible after compensation.
        Next = "OrderCancelled"
      }
      OrderCancelled = {
        Type  = "Fail"
        Error = "OrderCancelled"
        Cause = "The order was cancelled and compensation was attempted."
      }
    }
  })

  # The role policy's resources are predictable ARNs, so this does not form a dependency cycle.
  depends_on = [aws_iam_role_policy.sfn]
}
