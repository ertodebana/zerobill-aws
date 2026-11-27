variable "aws_region" {
  description = "AWS Region for the example."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix for the resources created by this example."
  type        = string
  default     = "daily-digest"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,40}$", var.name))
    error_message = "Use 1-40 lowercase letters, numbers, or hyphens."
  }
}

variable "alert_email" {
  description = "Email address that receives the daily digest and failure notices."
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.alert_email))
    error_message = "Enter a valid email address."
  }
}

variable "schedule_expression" {
  description = "A daily-or-slower Scheduler cron expression. The free Step Functions allowance is shared across the account."
  type        = string
  default     = "cron(0 6 * * ? *)"

  validation {
    condition     = can(regex("^cron\\([0-5]?[0-9] (1?[0-9]|2[0-3]) \\S+ \\S+ \\S+ \\S+\\)$", var.schedule_expression))
    error_message = "At most one run per day: cron(<minute> <hour> ...) with single integers. rate() and hourly schedules would exhaust the 4,000 Step Functions transitions."
  }
}

variable "schedule_timezone" {
  description = "IANA time zone used by EventBridge Scheduler."
  type        = string
  default     = "UTC"
}

variable "schedule_state" {
  description = "Enable or pause the daily schedule."
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.schedule_state)
    error_message = "schedule_state must be ENABLED or DISABLED."
  }
}

variable "min_magnitude" {
  description = "Minimum earthquake magnitude in the USGS query."
  type        = number
  default     = 2.5

  validation {
    condition     = var.min_magnitude >= 2.5 && var.min_magnitude <= 9
    error_message = "Use a magnitude from 2.5 through 9 to keep the daily query bounded."
  }
}

variable "top_n" {
  description = "Number of strongest events listed in each email."
  type        = number
  default     = 5

  validation {
    condition     = var.top_n >= 1 && var.top_n <= 10 && floor(var.top_n) == var.top_n
    error_message = "top_n must be an integer from 1 through 10."
  }
}

variable "retention_days" {
  description = "DynamoDB TTL retention period. Keep at least two days for the previous-day comparison."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days >= 2 && var.retention_days <= 90 && floor(var.retention_days) == var.retention_days
    error_message = "retention_days must be an integer from 2 through 90."
  }
}
