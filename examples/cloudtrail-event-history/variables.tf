variable "aws_region" {
  description = "AWS region for the example. Event history is per region; IAM and console sign-in events land in us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "function_name" {
  description = "Name for the digest Lambda function, its log group and roles."
  type        = string
  default     = "cloudtrail-digest"
}

variable "schedule_expression" {
  description = "EventBridge Scheduler expression for the digest run."
  type        = string
  default     = "rate(1 day)"

  validation {
    condition     = startswith(var.schedule_expression, "rate(") || startswith(var.schedule_expression, "cron(")
    error_message = "schedule_expression must start with rate( or cron(."
  }
}

variable "lookback_hours" {
  description = "How many hours of event history each run looks back."
  type        = number
  default     = 24

  validation {
    condition     = var.lookback_hours >= 1 && var.lookback_hours <= 168
    error_message = "lookback_hours must be between 1 and 168."
  }
}

variable "max_events" {
  description = "Maximum events per run (one LookupEvents page, API max 50)."
  type        = number
  default     = 50

  validation {
    condition     = var.max_events >= 1 && var.max_events <= 50
    error_message = "max_events must be between 1 and 50."
  }
}
