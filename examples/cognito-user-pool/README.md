# Cognito user pool

Creates a Cognito user pool on the Lite tier. You make a test user from the CLI, sign in with `initiate-auth` and read the ID, access and refresh tokens that come back. A free `amazoncognito.com` prefix domain also gives you the classic hosted sign-in page to try in a browser.

Resources created:

- `aws_cognito_user_pool.this`: pool `cognito-demo`. It uses tier `LITE`, email as the username and admin-only user creation. MFA is off, it sends email through the Cognito default sender, and deletion protection is off.
- `aws_cognito_user_pool_client.this`: a public app client with no secret. It allows SRP, password and refresh auth, plus the OAuth authorization code flow. Token lifetimes are short (60 min access/ID, 1 day refresh).
- `aws_cognito_user_pool_domain.this`: the prefix domain `<prefix>.auth.<region>.amazoncognito.com` with the classic hosted UI (`managed_login_version = 1`).

There is no identity pool, IAM role, SES, SNS, custom domain, Lambda trigger or external identity provider.

## Always Free and cost notes

See the [AWS Free Tier page](https://aws.amazon.com/free/) and [Cognito pricing](https://aws.amazon.com/cognito/pricing/).

- **10,000 direct-sign-in MAUs per month** per account or organization, on the Lite and Essentials tiers only. This allowance doesn't expire after 12 months. It is shared by every user pool in the account or organization.
- **Plus has no free tier.** Every Plus MAU is billed.
- **New pools default to Essentials.** That is why this example pins `user_pool_tier = "LITE"`: overage on Lite costs less than on Essentials.
- **Federated (SAML/OIDC) users get 50 free MAUs per month.** This example has no identity providers.
- **Machine-to-machine (`client_credentials`) tokens have no free tier.** The client doesn't allow that flow, and there is no resource server.
- **Threat protection (advanced security) has no free tier.** On Lite it is a paid add-on. It is off by default, and this example leaves out the `user_pool_add_ons` block so it stays off.
- **SMS bills at SNS rates.** MFA is off, there is no phone attribute and no SMS configuration.
- **Email:** the Cognito default sender costs nothing but has a low daily limit (see [Cognito quotas](https://docs.aws.amazon.com/cognito/latest/developerguide/quotas.html) and [email settings](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-email.html)). The steps below send no email.
- The prefix domain and hosted UI have no charge.

**What counts as an MAU:** a user who has an identity operation in the calendar month, such as a sign-in, token refresh or password change. Creating a user who never signs in doesn't count.

Don't enable self sign-up, SMS, MFA, the Plus tier, threat protection, federation or a custom domain until you have read the pricing page. With self sign-up on, anyone who finds the hosted UI URL can register and become an MAU.

## Requirements

- Terraform >= 1.5.0 and AWS provider >= 5.95.0 (the first release with both `user_pool_tier` and `managed_login_version`)
- AWS CLI configured with an IAM Identity Center profile
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials
- IAM permissions on `arn:aws:cognito-idp:<region>:<account>:userpool/*`:
  - `cognito-idp:CreateUserPool`, `DeleteUserPool`, `DescribeUserPool`, `UpdateUserPool`
  - `cognito-idp:GetUserPoolMfaConfig`, `SetUserPoolMfaConfig`
  - `cognito-idp:CreateUserPoolClient`, `DeleteUserPoolClient`, `DescribeUserPoolClient`, `UpdateUserPoolClient`
  - `cognito-idp:CreateUserPoolDomain`, `DeleteUserPoolDomain`, `DescribeUserPoolDomain`, `UpdateUserPoolDomain`
  - `cognito-idp:TagResource`, `UntagResource`, `ListTagsForResource`
  - `cognito-idp:AdminCreateUser`, `AdminSetUserPassword`, `AdminDeleteUser`
- `cognito-idp:DescribeUserPoolDomain` may need `Resource: "*"`, because the domain is looked up by name rather than by pool ARN.
- `InitiateAuth` is unauthenticated, so it needs no IAM permission.

## Use

`domain_prefix` has no default. Pick one that is unique in the region, using lowercase letters, digits and hyphens, without `aws`, `amazon` or `cognito`.

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan -var domain_prefix=my-demo-1234
terraform apply -var domain_prefix=my-demo-1234
```

Create a user and sign in:

```sh
POOL=$(terraform output -raw user_pool_id)
CLIENT=$(terraform output -raw client_id)
EMAIL=you@example.com

# 1. Create the user. SUPPRESS means no invitation email is sent.
aws cognito-idp admin-create-user --user-pool-id "$POOL" --username "$EMAIL" --message-action SUPPRESS

# 2. Set a permanent password from a prompt, so it never lands in a file.
#    It needs 12+ characters with upper, lower, digit and symbol.
read -s -p "Password: " PASSWORD; echo
aws cognito-idp admin-set-user-password --user-pool-id "$POOL" --username "$EMAIL" --password "$PASSWORD" --permanent

# 3. Sign in and decode the ID token payload.
aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id "$CLIENT" \
  --auth-parameters USERNAME="$EMAIL",PASSWORD="$PASSWORD" \
  --query AuthenticationResult.IdToken --output text | cut -d. -f2 | base64 -d 2>/dev/null; echo
unset PASSWORD
```

`base64 -d` may complain about missing padding. The JSON still prints. The client allows `USER_PASSWORD_AUTH` only for this CLI demo. Real apps should use SRP (`USER_SRP_AUTH`), which never sends the password.

4. Run `terraform output -raw hosted_ui_url`, open the URL in a browser and sign in. The browser is sent to `http://localhost:8000/callback?code=...`. The page fails to load because nothing is listening, which is fine: the `code` in the address bar is the authorization code.

`issuer_url` is the OIDC issuer for checking tokens (`<issuer_url>/.well-known/openid-configuration`).

## Cleanup

```sh
aws cognito-idp admin-delete-user --user-pool-id "$POOL" --username "$EMAIL"   # optional, destroy removes it too
terraform plan -destroy -var domain_prefix=my-demo-1234
terraform destroy -var domain_prefix=my-demo-1234
```

Deletion protection is `INACTIVE`, and Terraform deletes the domain before the pool. Then check:

- `aws cognito-idp list-user-pools --max-results 60 --region <region>` shows no `cognito-demo`.
- `aws cognito-idp describe-user-pool-domain --domain <prefix>` returns an empty `DomainDescription`.
- `terraform state list` is empty.
- In Billing > Free Tier, Cognito MAUs are in the single digits and there are no SNS SMS charges.
