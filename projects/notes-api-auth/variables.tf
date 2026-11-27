variable "aws_region" {
  description = "AWS region for the project."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix used for project resources."
  type        = string
  default     = "notes-api"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,32}$", var.name))
    error_message = "name must contain 3–32 lowercase letters, digits, or hyphens."
  }
}

variable "cors_allow_origins" {
  description = "Exact browser origins allowed by the function URL."
  type        = list(string)
  default     = ["http://localhost:8000"]

  validation {
    condition     = length(var.cors_allow_origins) > 0 && alltrue([for origin in var.cors_allow_origins : origin != "*"])
    error_message = "cors_allow_origins must contain at least one origin and cannot include a wildcard."
  }
}

variable "read_capacity" {
  description = "Provisioned DynamoDB read capacity units."
  type        = number
  default     = 2

  validation {
    condition     = var.read_capacity >= 1 && var.read_capacity <= 5
    error_message = "read_capacity must be between 1 and 5."
  }
}

variable "write_capacity" {
  description = "Provisioned DynamoDB write capacity units."
  type        = number
  default     = 1

  validation {
    condition     = var.write_capacity >= 1 && var.write_capacity <= 5
    error_message = "write_capacity must be between 1 and 5."
  }
}

variable "reserved_concurrency" {
  description = "Optional Lambda concurrency cap (0–5); null leaves account concurrency unreserved."
  type        = number
  default     = null
  nullable    = true

  validation {
    condition     = var.reserved_concurrency == null || (var.reserved_concurrency >= 0 && var.reserved_concurrency <= 5)
    error_message = "reserved_concurrency must be null or between 0 and 5."
  }
}

variable "enable_xray" {
  description = "Enable Lambda active tracing and the corresponding X-Ray write permissions."
  type        = bool
  default     = false
}
