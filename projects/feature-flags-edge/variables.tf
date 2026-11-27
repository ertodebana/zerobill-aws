variable "aws_region" {
  description = "AWS region for Lambda and DynamoDB. CloudFront is global."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix used for this project's AWS resource names."
  type        = string
  default     = "feature-flags-edge"
}

variable "cache_ttl_seconds" {
  description = "CloudFront shared-cache TTL. The CloudFront Function still runs on every viewer request."
  type        = number
  default     = 60

  validation {
    condition     = var.cache_ttl_seconds >= 10 && var.cache_ttl_seconds <= 300
    error_message = "cache_ttl_seconds must be between 10 and 300 seconds."
  }
}

variable "distribution_enabled" {
  description = "Set false to pause the public CloudFront endpoint without deleting the distribution."
  type        = bool
  default     = true
}
