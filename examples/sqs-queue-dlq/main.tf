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

  default_tags {
    tags = {
      Example   = "sqs-queue-dlq"
      ManagedBy = "Terraform"
    }
  }
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.queue_name}-dlq"
  message_retention_seconds = 86400
  sqs_managed_sse_enabled   = true
  max_message_size          = 65536
  receive_wait_time_seconds = 20
}

resource "aws_sqs_queue" "main" {
  name                       = var.queue_name
  message_retention_seconds  = 3600
  visibility_timeout_seconds = 30
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
