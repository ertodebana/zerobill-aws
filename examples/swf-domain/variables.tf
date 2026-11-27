variable "aws_region" {
  description = "AWS region for the example. Verify the offer is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "domain_name_prefix" {
  description = "Prefix for the SWF domain name. Terraform appends a unique suffix."
  type        = string
  default     = "swf-learning-"
}

variable "retention_days" {
  description = "Days closed executions are retained (and count as workflow-days). Limited to 0-7 here; the provider allows up to 90."
  type        = number
  default     = 1

  validation {
    condition     = var.retention_days >= 0 && var.retention_days <= 7 && floor(var.retention_days) == var.retention_days
    error_message = "retention_days must be a whole number from 0 to 7."
  }
}
