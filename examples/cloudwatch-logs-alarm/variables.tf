variable "aws_region" {
  description = "AWS region for the example. Verify the offer is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Name used for the log group, metric filter, alarm and dashboard."
  type        = string
  default     = "cloudwatch-demo"
}

variable "log_retention_days" {
  description = "Log retention in days. Kept short to bound stored log volume."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3, 5, 7], var.log_retention_days)
    error_message = "log_retention_days must be one of 1, 3, 5, 7."
  }
}
