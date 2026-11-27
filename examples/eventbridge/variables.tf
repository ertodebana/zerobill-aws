variable "aws_region" {
  description = "AWS region for the example. Verify the offer is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for the function, roles, log group and schedule."
  type        = string
  default     = "eventbridge-demo"
}

variable "schedule_expression" {
  description = "Scheduler expression, e.g. rate(1 hour), rate(5 minutes), cron(...) or at(...). Sub-minute rates are rejected."
  type        = string
  default     = "rate(1 hour)"

  validation {
    condition     = can(regex("^(rate\\([1-9][0-9]* (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\)|at\\(.+\\))$", var.schedule_expression))
    error_message = "Use rate(N minute[s]|hour[s]|day[s]), cron(...) or at(...). Second-based rates are not allowed."
  }
}

variable "schedule_state" {
  description = "ENABLED runs the schedule; DISABLED pauses it."
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.schedule_state)
    error_message = "schedule_state must be ENABLED or DISABLED."
  }
}
