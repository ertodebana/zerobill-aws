variable "aws_region" {
  description = "ECR Public's API exists only in us-east-1. Images are still pullable globally."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "ECR Public repositories can only be created in us-east-1."
  }
}

variable "repository_name" {
  description = "Name of the public repository. It is visible to everyone."
  type        = string
  default     = "ecr-public-learning"

  validation {
    condition     = length(var.repository_name) >= 2 && length(var.repository_name) <= 205 && can(regex("^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*$", var.repository_name))
    error_message = "repository_name must be 2-205 chars of lowercase letters, digits and . _ - / separators."
  }
}
