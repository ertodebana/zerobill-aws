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
}

data "aws_caller_identity" "current" {}

locals {
  tags = {
    Example   = "step-functions-hello"
    ManagedBy = "Terraform"
  }
}

# No inline or managed policies are attached: the workflow uses only built-in
# states (Pass, Choice, Succeed, Fail) and calls no other AWS service.
# Logging and tracing are off, so no CloudWatch Logs or X-Ray permissions either.
resource "aws_iam_role" "sfn" {
  name = "${var.state_machine_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })

  tags = local.tags
}

resource "aws_sfn_state_machine" "hello" {
  name     = var.state_machine_name
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD" # Express has no free tier; keep this a literal.

  logging_configuration {
    level = "OFF"
  }

  tracing_configuration {
    enabled = false
  }

  definition = jsonencode({
    Comment = "Hello workflow using only built-in states."
    StartAt = "CheckInput"
    States = {
      # Validate first, so bad input ends in BadInput instead of a States.Runtime error in Greet.
      CheckInput = {
        Type = "Choice"
        Choices = [{
          Or = [
            { Not = { Variable = "$.name", IsPresent = true } },
            { Not = { Variable = "$.loud", IsPresent = true } },
            { Not = { Variable = "$.loud", IsBoolean = true } },
          ]
          Next = "BadInput"
        }]
        Default = "Greet"
      }
      Greet = {
        Type = "Pass"
        Parameters = {
          "greeting.$" = "States.Format('Hello, {}!', $.name)"
          "loud.$"     = "$.loud"
        }
        Next = "IsLoud"
      }
      IsLoud = {
        Type = "Choice"
        Choices = [{
          Variable      = "$.loud"
          BooleanEquals = true
          Next          = "Shout"
        }]
        Default = "Done"
      }
      Shout = {
        Type = "Pass"
        Parameters = {
          "greeting.$" = "States.Format('{} (LOUD)', $.greeting)"
        }
        Next = "Done"
      }
      Done = {
        Type = "Succeed"
      }
      BadInput = {
        Type  = "Fail"
        Error = "BadInput"
        Cause = "name and loud are required; loud must be a boolean"
      }
    }
  })

  tags = local.tags
}
