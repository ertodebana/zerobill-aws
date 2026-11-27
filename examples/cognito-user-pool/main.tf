terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # user_pool_tier needs 5.83.0, managed_login_version needs 5.95.0.
      version = ">= 5.95.0, < 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # The pool takes tags. The client and domain resources don't support tags.
  default_tags {
    tags = {
      Example   = "cognito-user-pool"
      ManagedBy = "Terraform"
    }
  }
}

resource "aws_cognito_user_pool" "this" {
  name                = var.pool_name
  user_pool_tier      = "LITE" # New pools default to ESSENTIALS. PLUS has no free tier.
  deletion_protection = "INACTIVE"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OFF"

  admin_create_user_config {
    allow_admin_create_user_only = true # no self sign-up, so strangers can't create MAUs
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 1
  }

  # No user_pool_add_ons block: threat protection (paid, no free tier) is off by default.
}

resource "aws_cognito_user_pool_client" "this" {
  name            = "${var.pool_name}-client"
  user_pool_id    = aws_cognito_user_pool.this.id
  generate_secret = false

  # USER_PASSWORD_AUTH is only here for the CLI demo. Real apps should use SRP.
  explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  callback_urls                        = [var.callback_url]
  logout_urls                          = [var.callback_url]
  supported_identity_providers         = ["COGNITO"]

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 1
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
}

resource "aws_cognito_user_pool_domain" "this" {
  domain                = var.domain_prefix
  user_pool_id          = aws_cognito_user_pool.this.id
  managed_login_version = 1 # classic hosted UI; managed login (2) needs Essentials
}
