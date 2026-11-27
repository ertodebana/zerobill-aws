# CloudFront in front of a private Lambda function URL

Creates a CloudFront distribution on the default `*.cloudfront.net` hostname, with a Lambda function URL as its only origin. The function URL uses `AWS_IAM` auth, and CloudFront signs origin requests with Origin Access Control (OAC), so only this distribution can call it. A direct call to the URL returns 403. The origin sends `Cache-Control: public, max-age=300`, so you can watch `x-cache` go from `Miss from cloudfront` to `Hit from cloudfront`. No S3, because S3 is not an Always Free service.

## What it builds

1. `aws_iam_role.lambda`: execution role trusted by `lambda.amazonaws.com` only
2. `aws_iam_role_policy.logs`: `logs:CreateLogStream` and `logs:PutLogEvents` on this function's log group only
3. `aws_cloudwatch_log_group.lambda`: `/aws/lambda/cloudfront-demo`, 7-day retention
4. `aws_lambda_function.origin`: python3.12, 128 MB, 3 s timeout, returns a small HTML page with its generation timestamp
5. `aws_lambda_function_url.origin`: `AWS_IAM` auth, `BUFFERED`, no CORS
6. `aws_lambda_permission.cloudfront_url`: `lambda:InvokeFunctionUrl` for `cloudfront.amazonaws.com`, scoped to this distribution
7. `aws_lambda_permission.cloudfront_invoke`: `lambda:InvokeFunction` for `cloudfront.amazonaws.com`, scoped to this distribution (current AWS docs require both)
8. `aws_cloudfront_origin_access_control.lambda`: origin type `lambda`, always sign, SigV4
9. `aws_cloudfront_distribution.this`: one origin, one GET/HEAD behavior using the managed `CachingOptimized` cache policy, `PriceClass_100`, default certificate

All resources are tagged `Example = "cloudfront-lambda-url"` and `ManagedBy = "Terraform"`.

## Always Free and cost notes

| Dimension | Always Free limit | This example | Source |
|---|---|---|---|
| CloudFront data transfer out | 1 TB/month | < 10 MB | [CloudFront pay-as-you-go pricing](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/) |
| CloudFront HTTP/HTTPS requests | 10,000,000/month | < 1,000 | [CloudFront pay-as-you-go pricing](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/) |
| CloudFront Function invocations / KeyValueStore reads | 2,000,000 each/month | 0 (not used) | [CloudFront pay-as-you-go pricing](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/) |
| Origin fetch from AWS origins | Free | < 100 cache misses | [CloudFront pay-as-you-go pricing](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/) |
| Data from CloudFront to origin (POST/PUT bodies) | No free allowance ($0.020/GB in the US) | 0, only GET and HEAD allowed | [CloudFront pay-as-you-go pricing](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/) |
| Invalidations | First 1,000 paths/month, then $0.005/path | 0 to a few (`/*` counts as 1) | [CloudFront pay-as-you-go pricing](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/) |
| Lambda requests | 1,000,000/month (shared by all functions in the account) | < 100 | [AWS Free Tier](https://aws.amazon.com/free/), [Lambda pricing](https://aws.amazon.com/lambda/pricing/) |
| Lambda compute | 400,000 GB-s/month | about 1.25 GB-s | [AWS Free Tier](https://aws.amazon.com/free/) |
| CloudWatch Logs | 5 GB/month | < 1 MB, 7-day retention | [AWS Free Tier](https://aws.amazon.com/free/) |
| CloudFront default metrics | Free (standard 6 metrics) | default only | [CloudFront pay-as-you-go pricing](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/) |

- **Function URL:** the [Lambda pricing page](https://aws.amazon.com/lambda/pricing/) has no separate function URL line item. Invocations count as normal Lambda requests and duration.
- **Origin fetch is free.** Fetches from AWS origins such as Lambda to the edge are free of charge. Only the cached bodies sent to viewers count against the 1 TB.
- **Invalidations:** the first 1,000 paths per month are free. Use a single `/*` invalidation, which counts as one path.
- **Flat-rate plans:** CloudFront also sells flat-rate plans (Free, Pro, Business, Premium). They are opt-in per distribution and this example does not use them. A plan needs an AWS WAF web ACL, accounts using AWS Free Tier are not eligible, and the plan's Free tier allowances are smaller than Always Free. Always Free applies on default pay-as-you-go pricing. Don't subscribe this distribution to a plan in the console: paid tiers bill monthly, and a distribution on a plan can't be deleted until the plan is cancelled. See [CloudFront pricing](https://aws.amazon.com/cloudfront/pricing/) and the [flat-rate plan docs](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/flat-rate-pricing-plan.html).
- **Public endpoint, flood risk:** the `*.cloudfront.net` hostname is public and there is no WAF (WAF is paid). Past 10M requests or 1 TB in a month, pay-as-you-go rates apply. Caching and GET/HEAD only limit what reaches Lambda (`CachingOptimized` ignores query strings, headers and cookies), but CloudFront requests are still counted. Set a billing alarm (see [HOWTO.md](../../HOWTO.md)), use `distribution_enabled = false` to pause, and **destroy the stack when done**.
- **Price class:** `PriceClass_100` only lowers rates above the free allowance. It doesn't block viewers elsewhere.
- **Left off on purpose (each one bills):** real-time logs (Kinesis), standard logging, Lambda@Edge, additional metrics (monitoring subscription), origin shield, field-level encryption, dedicated-IP SSL, Anycast static IPs, continuous deployment, custom domain/ACM, Route 53, WAF. Also no reserved concurrency on the function.

## Requirements

- Terraform installed
- AWS CLI configured with an IAM Identity Center profile
- Permissions to create/delete CloudFront distributions and origin access controls, Lambda functions, function URLs and permissions, IAM roles/inline policies (including `iam:PassRole` for the execution role), and CloudWatch log groups
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Apply takes about 5 minutes, because Terraform waits for the distribution to deploy to the edge.

1. Run the `test_command` output twice. The first response shows `x-cache: Miss from cloudfront`, the second `Hit from cloudfront` with a growing `age`. The timestamp in the body stays the same until the 300 s max-age runs out.
2. Call the function URL directly: `curl -i "$(terraform output -raw function_url)"`. It returns 403, because only CloudFront's signed requests are allowed.
3. Run the `invalidate_command` output once, then curl again to see a fresh Miss.
4. To pause without deleting, set `distribution_enabled = false` and apply again.

## Cleanup

```sh
terraform plan -destroy
terraform destroy
```

Destroy can take about 15 minutes, because Terraform must disable the distribution and wait for that to deploy before deleting it.

Then check:

- `aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='cloudfront-demo']"` returns empty.
- `aws cloudfront list-origin-access-controls` shows no `cloudfront-demo` OAC.
- `aws lambda get-function --function-name cloudfront-demo` returns ResourceNotFound.
- `aws logs describe-log-groups --log-group-name-prefix /aws/lambda/cloudfront-demo` is empty. If Lambda recreated it, delete it by hand.
- `aws iam get-role --role-name cloudfront-demo-role` returns NoSuchEntity.
- Billing > Free Tier shows CloudFront and Lambda usage well under the limits, and Billing shows no flat-rate plan subscription.
