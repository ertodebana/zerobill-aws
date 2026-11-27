variable "aws_region" {
  description = "AWS region for the example. Verify the offer is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "pool_name" {
  description = "Name for the user pool. The app client is named <pool_name>-client."
  type        = string
  default     = "cognito-demo"
}

variable "domain_prefix" {
  description = "Prefix for <prefix>.auth.<region>.amazoncognito.com. It must be unique in the region."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$", var.domain_prefix)) && !can(regex("aws|amazon|cognito", var.domain_prefix))
    error_message = "Use lowercase letters, digits and hyphens only (no leading or trailing hyphen), and don't include aws, amazon or cognito."
  }
}

variable "callback_url" {
  description = "OAuth callback and sign-out URL. Nothing needs to be listening there."
  type        = string
  default     = "http://localhost:8000/callback"
}
