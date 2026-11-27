variable "aws_region" {
  description = "AWS region for the example. Verify the offer is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name for the CodeBuild project; also used for the log group and IAM role."
  type        = string
  default     = "codebuild-learning"
}

variable "compute_type" {
  description = "CodeBuild compute type. Pinned to BUILD_GENERAL1_SMALL (general1.small), the only x86_64 type in the Always Free 100 build minutes."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"

  validation {
    condition     = var.compute_type == "BUILD_GENERAL1_SMALL"
    error_message = "Only BUILD_GENERAL1_SMALL is covered by the Always Free build minutes."
  }
}

variable "environment_type" {
  description = "CodeBuild environment type. Pinned to LINUX_CONTAINER. Trap: BUILD_GENERAL1_SMALL with LINUX_GPU_CONTAINER is the paid 'Linux GPU Small' type, not general1.small."
  type        = string
  default     = "LINUX_CONTAINER"

  validation {
    condition     = var.environment_type == "LINUX_CONTAINER"
    error_message = "Only LINUX_CONTAINER keeps BUILD_GENERAL1_SMALL on the free general1.small type."
  }
}

variable "image" {
  description = "Curated CodeBuild image (Amazon Linux 2023 x86_64 standard 5.0)."
  type        = string
  default     = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
}

variable "build_timeout_minutes" {
  description = "Hard cap on each build's duration, in minutes."
  type        = number
  default     = 5

  validation {
    condition     = var.build_timeout_minutes >= 5 && var.build_timeout_minutes <= 10
    error_message = "build_timeout_minutes must be between 5 and 10."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for build logs, in days."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3, 5, 7], var.log_retention_days)
    error_message = "log_retention_days must be one of 1, 3, 5, 7."
  }
}
