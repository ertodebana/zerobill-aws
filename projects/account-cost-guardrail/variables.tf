variable "aws_region" {
  description = "AWS region. Must be us-east-1: billing metrics exist only there."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "Billing metrics exist only in us-east-1; the alarm and its SNS topic must be there."
  }
}

variable "name" {
  description = "Name prefix for every resource. Deploy only one copy per account."
  type        = string
  default     = "cost-guardrail"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,40}$", var.name))
    error_message = "name must be 1-40 characters of lowercase letters, digits and hyphens."
  }
}

variable "alert_email" {
  description = "Email address that receives budget and billing alarm notifications."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "budget_limit_usd" {
  description = "Monthly budget limit in USD. The brake fires at 100% of actual spend."
  type        = string
  default     = "2"

  validation {
    condition     = can(tonumber(var.budget_limit_usd)) && try(tonumber(var.budget_limit_usd) > 0 && tonumber(var.budget_limit_usd) <= 100, false)
    error_message = "budget_limit_usd must be a number greater than 0 and at most 100."
  }
}

variable "forecast_alert_percent" {
  description = "Forecasted-spend notification threshold, as a percent of the budget limit."
  type        = number
  default     = 50

  validation {
    condition     = var.forecast_alert_percent >= 1 && var.forecast_alert_percent <= 100
    error_message = "forecast_alert_percent must be between 1 and 100."
  }
}

variable "billing_alarm_threshold_usd" {
  description = "CloudWatch EstimatedCharges alarm threshold in USD."
  type        = number
  default     = 1

  validation {
    condition     = var.billing_alarm_threshold_usd > 0
    error_message = "billing_alarm_threshold_usd must be greater than 0."
  }
}

variable "sandbox_policy_arns" {
  description = "Permissions for experiments; widen deliberately."
  type        = set(string)
  default     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}

variable "brake_approval_model" {
  description = "AUTOMATIC applies the brake without asking; MANUAL waits for approval in the console."
  type        = string
  default     = "AUTOMATIC"

  validation {
    condition     = contains(["AUTOMATIC", "MANUAL"], var.brake_approval_model)
    error_message = "brake_approval_model must be AUTOMATIC or MANUAL."
  }
}
