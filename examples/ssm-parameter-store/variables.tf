variable "aws_region" {
  description = "AWS region for the example. Verify the offer is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "prefix" {
  description = "Parameter hierarchy prefix. Must start with / and must not end with /."
  type        = string
  default     = "/ssm-demo/app"

  validation {
    condition     = startswith(var.prefix, "/") && !endswith(var.prefix, "/")
    error_message = "prefix must start with \"/\" and must not end with \"/\"."
  }
}

variable "db_password" {
  description = "Dummy value for the demo SecureString. Never put a real secret here: it is stored in plaintext in terraform.tfstate."
  type        = string
  sensitive   = true
  default     = "change-me-demo-only"
}
