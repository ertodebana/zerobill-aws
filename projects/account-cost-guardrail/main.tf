terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Example   = "account-cost-guardrail"
      ManagedBy = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id        = data.aws_caller_identity.current.account_id
  sandbox_role_name = "${var.name}-sandbox"
}

# --- Alerts: SNS topic + email ---

# No KMS: Budgets cannot publish to a topic encrypted without a CMK, and a CMK costs $1/month.
resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

# This policy replaces the default topic policy. Same-account operators still
# manage the topic through their own IAM identity policies.
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowBudgets"
        Effect    = "Allow"
        Principal = { Service = "budgets.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:aws:budgets::${local.account_id}:*" }
        }
      },
      {
        Sid       = "AllowCloudWatchAlarm"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:aws:cloudwatch:us-east-1:${local.account_id}:alarm:${var.name}-*" }
        }
      },
    ]
  })
}

# Stays PendingConfirmation until the link in the email is clicked. Terraform
# can't delete a pending subscription; AWS expires it after 3 days.
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Signal 1: CloudWatch billing alarm (actual spend) ---

# Stays INSUFFICIENT_DATA until "Receive CloudWatch Billing Alerts" is enabled
# in the Billing console (one-way toggle, see README).
resource "aws_cloudwatch_metric_alarm" "estimated_charges" {
  alarm_name          = "${var.name}-estimated-charges"
  alarm_description   = "Actual estimated charges for the month exceed the threshold."
  namespace           = "AWS/Billing"
  metric_name         = "EstimatedCharges"
  dimensions          = { Currency = "USD" }
  statistic           = "Maximum"
  period              = 21600
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.billing_alarm_threshold_usd
  treat_missing_data  = "missing"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = []
}

# --- Signal 2: Budget (forecast + actual) ---

resource "aws_budgets_budget" "this" {
  name         = var.name
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Measure gross spend: credits would otherwise mask real usage.
  cost_types {
    include_credit = false
    include_refund = false
  }

  notification {
    notification_type         = "FORECASTED"
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.forecast_alert_percent
    threshold_type            = "PERCENTAGE"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  notification {
    notification_type         = "ACTUAL"
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  # Budgets checks publish access when the budget is created.
  depends_on = [aws_sns_topic_policy.alerts]
}

# --- Brake target: the sandbox role (the ONLY thing the brake can touch) ---

resource "aws_iam_role" "sandbox" {
  name                 = local.sandbox_role_name
  max_session_duration = 3600
  # Lets destroy succeed even if Budgets still has the brake attached.
  force_detach_policies = true

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
      Action    = "sts:AssumeRole"
    }]
  })

  # Destroy ordering: the role (and the force-detached brake with it) is
  # deleted BEFORE the brake policy, avoiding a DeleteConflict.
  depends_on = [aws_iam_policy.brake]
}

resource "aws_iam_role_policy_attachment" "sandbox" {
  for_each   = var.sandbox_policy_arns
  role       = aws_iam_role.sandbox.name
  policy_arn = each.value
}

# Separate managed policy so Budgets can attach and detach it cleanly.
# Terraform never attaches it itself.
resource "aws_iam_policy" "brake" {
  name        = "${var.name}-brake"
  description = "Attached by AWS Budgets to the sandbox role only. Denies everything."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
    }]
  })
}

# --- Budgets execution role: can attach ONE policy to ONE role ---

resource "aws_iam_role" "budgets_exec" {
  name = "${var.name}-budgets-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "budgets.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:budgets::${local.account_id}:budget/*" }
      }
    }]
  })
}

# Deliberately NOT the AWS managed AWSBudgetsActionsWithAWSResourceControlAccess
# policy, which is account-wide. No user/group attach, no organizations:*.
resource "aws_iam_role_policy" "budgets_exec" {
  name = "attach-brake-to-sandbox-only"
  role = aws_iam_role.budgets_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
      Resource = aws_iam_role.sandbox.arn
      Condition = {
        ArnEquals = { "iam:PolicyARN" = aws_iam_policy.brake.arn }
      }
    }]
  })
}

# --- The brake ---

resource "aws_budgets_budget_action" "brake" {
  budget_name        = aws_budgets_budget.this.name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = var.brake_approval_model
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budgets_exec.arn

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 100
  }

  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.brake.arn
      # Only the sandbox role. Never add users or groups here.
      roles = [aws_iam_role.sandbox.name]
    }
  }

  subscriber {
    subscription_type = "SNS"
    address           = aws_sns_topic.alerts.arn
  }

  depends_on = [aws_iam_role_policy.budgets_exec]

  lifecycle {
    precondition {
      condition     = !strcontains(data.aws_caller_identity.current.arn, ":assumed-role/${local.sandbox_role_name}/")
      error_message = "Do not run Terraform as the sandbox role; the brake would lock Terraform out."
    }
  }
}
