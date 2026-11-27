variable "aws_region" {
  description = "AWS region for the example."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix used for the resources in this example."
  type        = string
  default     = "order-saga"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,40}$", var.name))
    error_message = "name must contain 1 to 40 lowercase letters, numbers, or hyphens."
  }
}

variable "notification_email" {
  description = "Optional email address subscribed to order notifications."
  type        = string
  default     = ""
}

variable "function_url_auth_type" {
  description = "AWS_IAM protects the shared transition budget; NONE makes the URL public."
  type        = string
  default     = "AWS_IAM"

  validation {
    condition     = contains(["AWS_IAM", "NONE"], var.function_url_auth_type)
    error_message = "function_url_auth_type must be AWS_IAM or NONE."
  }
}

variable "place_order_reserved_concurrency" {
  description = "Optional concurrency cap. Leave null if the account quota does not allow reserved concurrency."
  type        = number
  default     = null

  validation {
    condition     = var.place_order_reserved_concurrency == null || (var.place_order_reserved_concurrency >= 1 && var.place_order_reserved_concurrency <= 5)
    error_message = "place_order_reserved_concurrency must be null or between 1 and 5."
  }
}

variable "order_ttl_days" {
  description = "Days to retain order records before DynamoDB TTL removes them."
  type        = number
  default     = 7

  validation {
    condition     = var.order_ttl_days >= 1 && var.order_ttl_days <= 30
    error_message = "order_ttl_days must be between 1 and 30."
  }
}
