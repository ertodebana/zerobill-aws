# Authenticated notes API

This project combines a Lite Cognito user pool, a public Lambda function URL, a provisioned DynamoDB table and CloudWatch Logs. It implements `POST`, `GET`, `PUT` and `DELETE` for a signed-in user's notes. The Lambda verifies Cognito access tokens locally and uses only the verified token `sub` as the DynamoDB partition key.

Review the account and CLI safety steps in [HOWTO.md](../../HOWTO.md) before creating AWS resources. The function URL is public and has no API Gateway in front of it. Keep the URL private and review its traffic and the account's Free Tier usage.

## Resources

Terraform creates these 10 resources:

- `aws_cognito_user_pool.this`: admin-created users only, Lite tier, MFA off, no self-sign-up or threat protection.
- `aws_cognito_user_pool_client.this`: public app client with SRP, password and refresh flows; no OAuth, hosted UI or client secret.
- `aws_dynamodb_table.notes`: provisioned table with `user_id` / `note_id` keys, no autoscaling, PITR, streams or extra indexes.
- `aws_cloudwatch_log_group.fn`: Lambda log group with 7-day retention.
- `aws_iam_role.fn`: Lambda execution role.
- `aws_iam_role_policy.fn`: log writes and five item-level DynamoDB actions; optional X-Ray writes are added only when enabled.
- `aws_lambda_function.api`: Node.js 22 function, 128 MB, 3-second timeout, with optional active tracing.
- `aws_lambda_function_url.api`: public HTTPS endpoint with a specific CORS origin allow-list.
- `aws_lambda_permission.url_invoke_url`: permits public function URL invocation when its auth type is `NONE`.
- `aws_lambda_permission.url_invoke_fn`: permits invocation through the function URL only.

There is no API Gateway because it is not an Always Free service. The Lambda uses Node's `node:crypto` to verify Cognito's RS256 JWT signature; this avoids a bundled JWT dependency and a dependency installation step. The DynamoDB SDK comes from the Node.js Lambda runtime.

## Always Free and cost notes

Check the current [AWS Free Tier offers](https://aws.amazon.com/free/) and [Cognito pricing](https://aws.amazon.com/cognito/pricing/) for your account, region and usage before deployment. Offers and account eligibility can change.

| Service / allowance | Limit | This project at typical learning usage |
|---|---:|---:|
| Cognito Lite direct-sign-in MAUs | 10,000/month per account or organization | 2 users for the isolation exercise |
| Lambda requests | 1 million/month | Under 5,000; an outsider can consume this allowance through the public URL |
| Lambda compute | 400,000 GB-seconds/month | Under 200 GB-seconds normally; 128 MB and 3 seconds bound each invocation |
| Function URL | No separate charge | Included in Lambda requests and duration |
| DynamoDB provisioned capacity | 25 RCU and 25 WCU per Region | 2 RCU and 1 WCU, shared with all other regional tables |
| DynamoDB storage | 25 GB | Under 1 MB |
| CloudWatch Logs | 5 GB ingestion and 5 GB storage/month | About 1.5 MB for 5,000 short log lines |
| X-Ray (optional) | 100,000 traces recorded/month | Off by default |
| Data transfer out | 100 GB/month shared allowance | Negligible for this exercise |

The default 2 RCU / 1 WCU use 2 of the regional 25 RCU and 1 of the 25 WCU. The table uses provisioned billing and the AWS-owned encryption key. Larger note bodies or rapid load scripts can throttle: the largest allowed note is about 2.4 KB, so one write can use 3 WCU. With 1 WCU configured, DynamoDB's burst capacity is intended for occasional interactive requests, not a load test.

## Authentication and data isolation

The client sends only a Cognito **access token** in `authorization: Bearer …`. The function checks the token's RS256 header, issuer, `token_use`, `client_id`, expiration, issue time, UUID `sub`, and signature. It fetches Cognito's JWKS on a cache miss, keeps the keys in the warm execution environment for up to an hour, and limits refresh attempts to one per minute. Authentication errors return a generic 401 and make no DynamoDB request. If the first JWKS fetch fails, the function returns 503.

The DynamoDB partition key always comes from the verified `sub`; request data cannot choose it. All callers share the Lambda role, so `dynamodb:LeadingKeys` cannot enforce user isolation. That condition would need per-user AWS credentials from an identity pool, which is outside this project.

Local JWT verification cannot discover a token that has been revoked after issuance. `GlobalSignOut` and token revocation therefore take effect for this API only when the 60-minute access token expires. If that delay is unacceptable, lower `access_token_validity` (minimum 5 minutes) and review the effect on sign-in traffic.

## Public URL and cost risks

The function URL uses `authorization_type = "NONE"`. Authentication happens inside the function, so every request, including an invalid one, invokes Lambda. A flood could use the account's 1-million-request allowance and create log volume. The function rejects malformed tokens before network or DynamoDB work, times out after 3 seconds, uses 128 MB, and cools down JWKS refreshes. Do not publish the URL.

An optional `reserved_concurrency` cap defaults to `null`. New accounts may have a concurrency quota too small for a reservation; the default does not reserve capacity. To stop new work immediately, use this kill switch:

```sh
aws lambda put-function-concurrency --function-name notes-api --reserved-concurrent-executions 0
```

This changes Lambda outside Terraform and creates drift. Undo the cap with:

```sh
aws lambda delete-function-concurrency --function-name notes-api
```

`terraform destroy` is the other cleanup path. A new function URL will have a new generated URL ID.

X-Ray is off by default. If enabled, it uses the account's shared trace allowance; turn it off when the endpoint is idle. Do not enable self-sign-up, SMS/MFA, Plus tier, advanced security, federation, a custom Cognito domain, DynamoDB on-demand billing or autoscaling without reviewing their pricing first.

## Provider version flag

This example requires AWS provider `>= 6.28.0, < 7.0`. HashiCorp added `invoked_via_function_url` to `aws_lambda_permission` in v6.28.0; the field is required to keep the public `lambda:InvokeFunction` permission limited to calls made through the function URL. The Cognito `user_pool_tier` setting also requires a newer provider than the repository's usual `~> 5.0`. Do not remove the invocation condition to retain provider 5.x. See the [provider change request and release note](https://github.com/hashicorp/terraform-provider-aws/issues/44829).

## Requirements and deployer permissions

- Terraform >= 1.5.0 and AWS provider >= 6.28.0, < 7.0.
- AWS CLI v2.
- An AWS identity with permission to manage the resources below. Scope actions to this project's resource names and ARNs where AWS supports resource-level permissions.

The deployer needs the following actions:

- Cognito: `cognito-idp:CreateUserPool`, `DeleteUserPool`, `DescribeUserPool`, `UpdateUserPool`, `GetUserPoolMfaConfig`, `SetUserPoolMfaConfig`, `CreateUserPoolClient`, `DeleteUserPoolClient`, `DescribeUserPoolClient`, `UpdateUserPoolClient`, `TagResource`, `UntagResource`, and `ListTagsForResource`. The CLI practice steps also use `AdminCreateUser`, `AdminSetUserPassword`, `AdminDeleteUser`, and unauthenticated `InitiateAuth`.
- DynamoDB: `dynamodb:CreateTable`, `DeleteTable`, `DescribeTable`, `UpdateTable`, `DescribeContinuousBackups`, `DescribeTimeToLive`, `ListTagsOfResource`, `TagResource`, and `UntagResource`.
- Lambda: `CreateFunction`, `DeleteFunction`, `GetFunction`, `UpdateFunctionCode`, `UpdateFunctionConfiguration`, `CreateFunctionUrlConfig`, `DeleteFunctionUrlConfig`, `GetFunctionUrlConfig`, `UpdateFunctionUrlConfig`, `AddPermission`, `RemovePermission`, `GetPolicy`, `PutFunctionConcurrency`, `DeleteFunctionConcurrency`, and `ListVersionsByFunction`.
- IAM: role create, delete, get and pass; inline policy put, get and delete. Restrict role and policy resources to `role/notes-api-*` (or the prefix selected with `name`).
- CloudWatch Logs: `logs:CreateLogGroup`, `logs:DeleteLogGroup`, `logs:DescribeLogGroups`, and `logs:PutRetentionPolicy`.

## Use

From this directory:

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
```

Review the plan, account ID, region, and resources before applying. When the plan is correct, create the resources with `terraform apply`. Create the two CLI-only users (use your own unique email addresses):

```sh
POOL_ID=$(terraform output -raw user_pool_id)
CLIENT_ID=$(terraform output -raw client_id)

aws cognito-idp admin-create-user --user-pool-id "$POOL_ID" --username you+notes-a@example.com --message-action SUPPRESS
aws cognito-idp admin-create-user --user-pool-id "$POOL_ID" --username you+notes-b@example.com --message-action SUPPRESS

read -s -p "Permanent password for both test users: " PASSWORD; echo
aws cognito-idp admin-set-user-password --user-pool-id "$POOL_ID" --username you+notes-a@example.com --password "$PASSWORD" --permanent
aws cognito-idp admin-set-user-password --user-pool-id "$POOL_ID" --username you+notes-b@example.com --password "$PASSWORD" --permanent

TOKEN_A=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id "$CLIENT_ID" \
  --auth-parameters USERNAME=you+notes-a@example.com,PASSWORD="$PASSWORD" \
  --query AuthenticationResult.AccessToken --output text)
TOKEN_B=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id "$CLIENT_ID" \
  --auth-parameters USERNAME=you+notes-b@example.com,PASSWORD="$PASSWORD" \
  --query AuthenticationResult.AccessToken --output text)
ID_TOKEN=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id "$CLIENT_ID" \
  --auth-parameters USERNAME=you+notes-a@example.com,PASSWORD="$PASSWORD" \
  --query AuthenticationResult.IdToken --output text)
unset PASSWORD
URL=$(terraform output -raw function_url)
```

Create a note and copy its returned `id` as `NOTE_ID`:

```sh
curl -i "$URL/notes" -H "authorization: Bearer $TOKEN_A" -H 'content-type: application/json' \
  -d '{"title":"First note","body":"Hello from the notes API"}'
NOTE_ID='paste-id-from-the-response-here'
```

List, read, update and delete it:

```sh
curl -i "$URL/notes" -H "authorization: Bearer $TOKEN_A"
curl -i "$URL/notes/$NOTE_ID" -H "authorization: Bearer $TOKEN_A"
curl -i -X PUT "$URL/notes/$NOTE_ID" -H "authorization: Bearer $TOKEN_A" \
  -H 'content-type: application/json' -d '{"title":"Updated","body":"Changed body"}'
curl -i -X DELETE "$URL/notes/$NOTE_ID" -H "authorization: Bearer $TOKEN_A"
```

To check per-user isolation, create another note with user A, then try to read, update and delete its ID as user B. Each request should return 404:

```sh
curl -i "$URL/notes/$NOTE_ID" -H "authorization: Bearer $TOKEN_B"
curl -i -X PUT "$URL/notes/$NOTE_ID" -H "authorization: Bearer $TOKEN_B" \
  -H 'content-type: application/json' -d '{"title":"Stolen","body":"No"}'
curl -i -X DELETE "$URL/notes/$NOTE_ID" -H "authorization: Bearer $TOKEN_B"
```

Authentication checks should return 401: omit the authorization header, send `ID_TOKEN` instead of the access token, or append a character to `TOKEN_A`. The response is generic and the log contains only the failure reason, never a token or body. Inspect recent logs with:

```sh
aws logs tail "/aws/lambda/notes-api" --since 10m
```

## Cleanup

```sh
terraform plan -destroy
terraform destroy
terraform state list
```

The final state list should be empty. Confirm that Lambda `notes-api`, its function URL and policy, the `/aws/lambda/notes-api` log group, DynamoDB table `notes-api-notes`, Cognito pool `notes-api`, and IAM role `notes-api-role` are gone. If the log group reappears after an invocation during destruction, delete it manually. After about a day, review Free Tier usage for Lambda requests, DynamoDB capacity, Cognito MAUs and X-Ray charges.
