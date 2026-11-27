variable "aws_region" {
  description = "AWS region. ECR Public is available only in us-east-1."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "ECR Public exists only in us-east-1."
  }
}

variable "name" {
  description = "Prefix used for the CodeBuild project, repository, logs, and notifications."
  type        = string
  default     = "ci-image-build"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,40}$", var.name))
    error_message = "name must be 2-40 lowercase letters, digits, or hyphens."
  }
}

variable "github_repo_url" {
  description = "Public GitHub repo you control. It is cloned anonymously over HTTPS."
  type        = string

  validation {
    condition     = can(regex("^https://github\\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\\.git)?$", var.github_repo_url))
    error_message = "github_repo_url must be an HTTPS URL for a public GitHub repository."
  }
}

variable "git_ref" {
  description = "Branch or tag cloned when the build does not override GIT_REF."
  type        = string
  default     = "main"
}

variable "dockerfile_path" {
  description = "Path to the Containerfile or Dockerfile inside the repository."
  type        = string
  default     = "Containerfile"
}

variable "alert_email" {
  description = "Email address that receives failed-build notifications. Confirm the SNS subscription after apply."
  type        = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "compute_type" {
  description = "Pinned to BUILD_GENERAL1_SMALL, the general1.small type covered by the free build-minute allowance."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"

  validation {
    condition     = var.compute_type == "BUILD_GENERAL1_SMALL"
    error_message = "Only BUILD_GENERAL1_SMALL is covered by the Always Free build minutes."
  }
}

variable "environment_type" {
  description = "Pinned to LINUX_CONTAINER. BUILD_GENERAL1_SMALL with LINUX_GPU_CONTAINER is a paid GPU type."
  type        = string
  default     = "LINUX_CONTAINER"

  validation {
    condition     = var.environment_type == "LINUX_CONTAINER"
    error_message = "Only LINUX_CONTAINER keeps BUILD_GENERAL1_SMALL on the free general1.small type."
  }
}

variable "image" {
  description = "AWS curated Amazon Linux 2023 x86_64 standard 5.0 CodeBuild image."
  type        = string
  default     = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
}

variable "build_timeout_minutes" {
  description = "Maximum duration of one build, in minutes."
  type        = number
  default     = 10

  validation {
    condition     = var.build_timeout_minutes >= 5 && var.build_timeout_minutes <= 10
    error_message = "build_timeout_minutes must be between 5 and 10."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7], var.log_retention_days)
    error_message = "log_retention_days must be one of 1, 3, 5, or 7."
  }
}

variable "schedule_expression" {
  description = "Optional EventBridge Scheduler rate expression. Use only rate(N days) where N is at least 7; null disables scheduling."
  type        = string
  default     = null

  validation {
    condition     = var.schedule_expression == null || can(regex("^rate\\(([7-9]|[1-9][0-9]+) days\\)$", var.schedule_expression))
    error_message = "Only rate(N days) with N >= 7 is allowed; daily builds would use most of the 100 free minutes."
  }
}
