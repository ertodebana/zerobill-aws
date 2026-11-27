variable "aws_region" {
  description = "AWS region for the project. Verify the offers are available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for every resource name."
  type        = string
  default     = "uptime-monitor"
}

variable "urls" {
  description = "1-3 URLs to check. Monitor only sites you own."
  type        = list(string)

  validation {
    condition     = length(var.urls) >= 1 && length(var.urls) <= 3 && alltrue([for u in var.urls : can(regex("^https?://", u))])
    error_message = "1-3 URLs; each URL is 1 custom metric + 1 alarm of the account's 10 free."
  }
}

variable "alert_email" {
  description = "Email address subscribed to the alerts topic. Confirm the subscription from the email AWS sends."
  type        = string

  validation {
    condition     = strcontains(var.alert_email, "@")
    error_message = "alert_email must be an email address."
  }
}

variable "check_interval_minutes" {
  description = "Minutes between checks: 5 (default) or 1. Both stay inside the Always Free limits."
  type        = number
  default     = 5

  validation {
    condition     = contains([1, 5], var.check_interval_minutes)
    error_message = "check_interval_minutes must be 1 or 5."
  }
}

variable "schedule_state" {
  description = "ENABLED runs the checks; DISABLED pauses them (alarms then go to ALARM, because missing data is breaching)."
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.schedule_state)
    error_message = "schedule_state must be ENABLED or DISABLED."
  }
}
