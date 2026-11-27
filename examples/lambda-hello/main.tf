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
}

data "archive_file" "function" {
  type        = "zip"
  source_file = "${path.module}/hello.py"
  output_path = "${path.module}/function.zip"
}

resource "aws_iam_role" "lambda" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 7
}

resource "aws_iam_role_policy" "logs" {
  name = "write-function-logs"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
    }]
  })
}

resource "aws_lambda_function" "hello" {
  function_name    = var.function_name
  role             = aws_iam_role.lambda.arn
  handler           = "hello.handler"
  runtime           = "python3.12"
  filename          = data.archive_file.function.output_path
  source_code_hash  = data.archive_file.function.output_base64sha256
  memory_size       = 128
  timeout           = 3
  publish           = false
  depends_on        = [aws_iam_role_policy.logs, aws_cloudwatch_log_group.lambda]
}
