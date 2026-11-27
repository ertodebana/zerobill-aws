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
      Example   = "cloudfront-lambda-url"
      ManagedBy = "Terraform"
    }
  }
}

data "archive_file" "function" {
  type        = "zip"
  source_file = "${path.module}/origin.py"
  output_path = "${path.module}/function.zip"
}

resource "aws_iam_role" "lambda" {
  name = "${var.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name}"
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
      Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
    }]
  })
}

resource "aws_lambda_function" "origin" {
  function_name    = var.name
  role             = aws_iam_role.lambda.arn
  handler          = "origin.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.function.output_path
  source_code_hash = data.archive_file.function.output_base64sha256
  memory_size      = 128
  timeout          = 3
  publish          = false

  environment {
    variables = {
      MAX_AGE = tostring(var.cache_max_age_seconds)
    }
  }

  depends_on = [aws_iam_role_policy.logs, aws_cloudwatch_log_group.lambda]
}

# AWS_IAM: direct calls without a SigV4 signature get 403. Never use "NONE".
resource "aws_lambda_function_url" "origin" {
  function_name      = aws_lambda_function.origin.function_name
  authorization_type = "AWS_IAM"
  invoke_mode        = "BUFFERED"
}

resource "aws_cloudfront_origin_access_control" "lambda" {
  name                              = var.name
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# No origin request policy: forwarding the viewer Host header breaks function URLs.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# Always Free applies on pay-as-you-go. Do not subscribe this distribution to a flat-rate plan.
resource "aws_cloudfront_distribution" "this" {
  enabled             = var.distribution_enabled
  comment             = var.name
  price_class         = "PriceClass_100"
  http_version        = "http2"
  is_ipv6_enabled     = true
  wait_for_deployment = true
  retain_on_delete    = false

  origin {
    domain_name              = trimsuffix(trimprefix(aws_lambda_function_url.origin.function_url, "https://"), "/")
    origin_id                = "lambda-url"
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "lambda-url"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# The current AWS docs require both statements for OAC to a function URL.
resource "aws_lambda_permission" "cloudfront_url" {
  statement_id           = "AllowCloudFrontInvokeFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.origin.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.this.arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "cloudfront_invoke" {
  statement_id  = "AllowCloudFrontInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.origin.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.this.arn
}
