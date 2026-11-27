variable "aws_region" {
  description = "AWS region for this project. Verify Always Free eligibility in your account and Region."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Lowercase prefix used to name this project's resources."
  type        = string
  default     = "webhook-ingest"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.name))
    error_message = "name must start with a lowercase letter and contain 3 to 31 lowercase letters, digits, or hyphens."
  }
}

variable "worker_enabled" {
  description = "Turns the SQS event source mapping on. While on, Lambda pollers make ~360-900 SQS requests/hour even when idle."
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Optional email address for DLQ alarm notifications. Confirm the subscription email."
  type        = string
  default     = ""
}

variable "max_body_bytes" {
  description = "Maximum decoded webhook body size. Keep this at or below 32 KB so the SQS message stays in one 64 KB request chunk."
  type        = number
  default     = 16384

  validation {
    condition     = var.max_body_bytes >= 1024 && var.max_body_bytes <= 32768
    error_message = "max_body_bytes must be between 1024 and 32768."
  }
}

variable "signature_tolerance_seconds" {
  description = "Maximum age or future skew accepted for a signed webhook timestamp."
  type        = number
  default     = 300

  validation {
    condition     = var.signature_tolerance_seconds >= 30 && var.signature_tolerance_seconds <= 900
    error_message = "signature_tolerance_seconds must be between 30 and 900."
  }
}

variable "dedup_ttl_days" {
  description = "Number of days to retain processed event IDs before DynamoDB TTL expires them."
  type        = number
  default     = 7

  validation {
    condition     = var.dedup_ttl_days >= 1 && var.dedup_ttl_days <= 30
    error_message = "dedup_ttl_days must be between 1 and 30."
  }
}

variable "table_read_capacity" {
  description = "Provisioned DynamoDB read capacity units."
  type        = number
  default     = 1

  validation {
    condition     = var.table_read_capacity >= 1 && var.table_read_capacity <= 5 && floor(var.table_read_capacity) == var.table_read_capacity
    error_message = "table_read_capacity must be a whole number from 1 through 5."
  }
}

variable "table_write_capacity" {
  description = "Provisioned DynamoDB write capacity units."
  type        = number
  default     = 2

  validation {
    condition     = var.table_write_capacity >= 1 && var.table_write_capacity <= 5 && floor(var.table_write_capacity) == var.table_write_capacity
    error_message = "table_write_capacity must be a whole number from 1 through 5."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention; choose a short supported value to bound stored logs."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7], var.log_retention_days)
    error_message = "log_retention_days must be one of 1, 3, 5, or 7."
  }
}

variable "ingest_reserved_concurrency" {
  description = "Optional cap for public ingest concurrency. Keep null on accounts where the concurrency quota is 10."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.ingest_reserved_concurrency == null || (var.ingest_reserved_concurrency >= 1 && var.ingest_reserved_concurrency <= 5 && floor(var.ingest_reserved_concurrency) == var.ingest_reserved_concurrency)
    error_message = "ingest_reserved_concurrency must be null or a whole number from 1 through 5."
  }
}
