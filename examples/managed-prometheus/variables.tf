variable "aws_region" {
  description = "AWS region for the example. Verify Amazon Managed Service for Prometheus is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Workspace alias and IAM policy name prefix."
  type        = string
  default     = "amp-demo"
}

variable "retention_days" {
  description = "Days AMP keeps samples. Kept short to bound stored data."
  type        = number
  default     = 7

  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 30
    error_message = "retention_days must be between 1 and 30."
  }
}
