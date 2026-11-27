variable "aws_region" {
  description = "AWS region for the Lambda origin. CloudFront itself is global."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name for the Lambda function, its log group, the OAC and the distribution comment."
  type        = string
  default     = "cloudfront-demo"
}

variable "cache_max_age_seconds" {
  description = "Cache-Control max-age the origin returns (passed to Lambda as MAX_AGE)."
  type        = number
  default     = 300

  validation {
    condition     = var.cache_max_age_seconds >= 0 && var.cache_max_age_seconds <= 86400
    error_message = "cache_max_age_seconds must be between 0 and 86400."
  }
}

variable "distribution_enabled" {
  description = "Set to false to pause the distribution without deleting it."
  type        = bool
  default     = true
}
