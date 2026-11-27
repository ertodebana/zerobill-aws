variable "aws_region" {
  description = "AWS region for the topic and queue. Verify the offer is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name for the SNS topic and SQS queue."
  type        = string
  default     = "sns-fanout-demo"
}

variable "email_endpoint" {
  description = "Optional email to subscribe; leave empty to skip. Must be confirmed via the email link."
  type        = string
  default     = ""
}
