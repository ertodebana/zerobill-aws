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
    Example   = "sns-fanout-sqs"
    ManagedBy = "Terraform"
  }
}

# Standard topic: no FIFO, no KMS, no delivery-status logging.
resource "aws_sns_topic" "this" {
  name = var.name
  tags = local.tags
}

resource "aws_sqs_queue" "this" {
  name                       = var.name
  sqs_managed_sse_enabled    = true
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 30
  receive_wait_time_seconds  = 10
  max_message_size           = 262144
  tags                       = local.tags
}

# Only this topic may send to the queue.
resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.this.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.this.arn }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "sqs" {
  topic_arn            = aws_sns_topic.this.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.this.arn
  raw_message_delivery = true
  depends_on           = [aws_sqs_queue_policy.this]
}

# Terraform can't delete a pending (unconfirmed) email subscription.
# AWS removes it after 3 days, and it costs nothing.
resource "aws_sns_topic_subscription" "email" {
  count     = var.email_endpoint == "" ? 0 : 1
  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = var.email_endpoint
}

output "topic_arn" {
  value = aws_sns_topic.this.arn
}

output "queue_url" {
  value = aws_sqs_queue.this.url
}

output "publish_command" {
  value = "aws sns publish --topic-arn ${aws_sns_topic.this.arn} --message \"hello\" --region ${var.aws_region}"
}

output "receive_command" {
  value = "aws sqs receive-message --queue-url ${aws_sqs_queue.this.url} --wait-time-seconds 10 --region ${var.aws_region}"
}
