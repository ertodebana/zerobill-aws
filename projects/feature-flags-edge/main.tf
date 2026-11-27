terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # function_url_auth_type scopes Lambda function URL invocation to AWS_IAM.
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
      Example   = "feature-flags-edge"
      ManagedBy = "Terraform"
    }
  }
}

data "archive_file" "origin" {
  type        = "zip"
  source_file = "${path.module}/origin.py"
  output_path = "${path.module}/build/origin.zip"
}

resource "aws_dynamodb_table" "flags" {
  name           = "${var.name_prefix}-flags"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "app"
  table_class    = "STANDARD"

  attribute {
    name = "app"
    type = "S"
  }

  point_in_time_recovery {
    enabled = false
  }

  stream_enabled              = false
  deletion_protection_enabled = false
}

resource "aws_dynamodb_table_item" "demo" {
  table_name = aws_dynamodb_table.flags.name
  hash_key   = aws_dynamodb_table.flags.hash_key

  item = jsonencode({
    app = { S = "demo" }
    flags = {
      M = {
        new_checkout = { BOOL = false }
        banner_text  = { S = "hello" }
      }
    }
  })

  lifecycle {
    # Operators change flags through the AWS CLI; Terraform must not undo those edits.
    ignore_changes = [item]
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name_prefix}-origin"
  retention_in_days = 7
}

resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-origin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.name_prefix}-origin-access"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = aws_dynamodb_table.flags.arn
      }
    ]
  })
}

resource "aws_lambda_function" "origin" {
  function_name    = "${var.name_prefix}-origin"
  role             = aws_iam_role.lambda.arn
  handler          = "origin.handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  filename         = data.archive_file.origin.output_path
  source_code_hash = data.archive_file.origin.output_base64sha256
  memory_size      = 128
  timeout          = 3
  publish          = false

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.flags.name
      CDN_TTL    = tostring(var.cache_ttl_seconds)
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.lambda]
}

resource "aws_lambda_function_url" "origin" {
  function_name      = aws_lambda_function.origin.function_name
  authorization_type = "AWS_IAM"
  invoke_mode        = "BUFFERED"
}

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

resource "aws_cloudfront_origin_access_control" "lambda" {
  name                              = var.name_prefix
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_cache_policy" "flags" {
  name        = "${var.name_prefix}-flags"
  min_ttl     = 0
  default_ttl = var.cache_ttl_seconds
  max_ttl     = var.cache_ttl_seconds

  # max_ttl caps the staleness promised to clients; measure Age because CloudFront
  # uses both edge and regional cache layers.
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }

    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

resource "aws_cloudfront_function" "normalize" {
  name    = "${var.name_prefix}-normalize"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/normalize.js")
  comment = "2M free invocations/mo; runs on every viewer request"
}

# Always Free applies on pay-as-you-go. Do not subscribe this distribution to a flat-rate plan.
resource "aws_cloudfront_distribution" "this" {
  enabled             = var.distribution_enabled
  comment             = var.name_prefix
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
    cache_policy_id        = aws_cloudfront_cache_policy.flags.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.normalize.arn
    }
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
