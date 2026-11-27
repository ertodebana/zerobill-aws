terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28.0, < 7.0"
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
      Example   = "notes-api-auth"
      ManagedBy = "Terraform"
    }
  }
}

resource "aws_cognito_user_pool" "this" {
  name                = var.name
  user_pool_tier      = "LITE"
  deletion_protection = "INACTIVE"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OFF"

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 1
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name            = "${var.name}-client"
  user_pool_id    = aws_cognito_user_pool.this.id
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  supported_identity_providers = ["COGNITO"]

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 1

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
}

resource "aws_dynamodb_table" "notes" {
  name                        = "${var.name}-notes"
  billing_mode                = "PROVISIONED"
  read_capacity               = var.read_capacity
  write_capacity              = var.write_capacity
  hash_key                    = "user_id"
  range_key                   = "note_id"
  deletion_protection_enabled = false

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "note_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = false
  }
}

resource "aws_cloudwatch_log_group" "fn" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = 7
}

resource "aws_iam_role" "fn" {
  name = "${var.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "fn" {
  name = "${var.name}-permissions"
  role = aws_iam_role.fn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = "${aws_cloudwatch_log_group.fn.arn}:*"
        },
        {
          Effect = "Allow"
          Action = [
            "dynamodb:PutItem",
            "dynamodb:GetItem",
            "dynamodb:Query",
            "dynamodb:UpdateItem",
            "dynamodb:DeleteItem",
          ]
          Resource = aws_dynamodb_table.notes.arn
        }
      ],
      var.enable_xray ? [
        {
          Effect   = "Allow"
          Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
          Resource = "*"
        }
      ] : []
    )
  })
}

data "archive_file" "fn" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/build/function.zip"
}

resource "aws_lambda_function" "api" {
  function_name    = var.name
  role             = aws_iam_role.fn.arn
  handler          = "index.handler"
  runtime          = "nodejs22.x"
  filename         = data.archive_file.fn.output_path
  source_code_hash = data.archive_file.fn.output_base64sha256
  memory_size      = 128
  timeout          = 3
  publish          = false

  reserved_concurrent_executions = var.reserved_concurrency == null ? -1 : var.reserved_concurrency

  environment {
    variables = {
      USER_POOL_ID = aws_cognito_user_pool.this.id
      CLIENT_ID    = aws_cognito_user_pool_client.this.id
      TABLE_NAME   = aws_dynamodb_table.notes.name
    }
  }

  tracing_config {
    mode = var.enable_xray ? "Active" : "PassThrough"
  }

  depends_on = [aws_iam_role_policy.fn, aws_cloudwatch_log_group.fn]
}

resource "aws_lambda_function_url" "api" {
  function_name      = aws_lambda_function.api.function_name
  authorization_type = "NONE"

  cors {
    allow_origins     = var.cors_allow_origins
    allow_methods     = ["GET", "POST", "PUT", "DELETE"]
    allow_headers     = ["authorization", "content-type"]
    max_age           = 300
    allow_credentials = false
  }
}

resource "aws_lambda_permission" "url_invoke_url" {
  statement_id           = "FunctionURLAllowPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.api.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "url_invoke_fn" {
  statement_id             = "FunctionURLInvokeAllowPublicAccess"
  action                   = "lambda:InvokeFunction"
  function_name            = aws_lambda_function.api.function_name
  principal                = "*"
  invoked_via_function_url = true
}
