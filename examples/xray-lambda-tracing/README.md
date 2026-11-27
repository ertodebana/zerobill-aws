# X-Ray Lambda tracing

Turns on X-Ray `Active` tracing for one minimal Lambda function. Invoke it a few times, then read the trace map and timeline (`AWS::Lambda` and `AWS::Lambda::Function` segments, including Init/cold-start timing). The function code has no X-Ray SDK; Lambda records the segments itself.

## Resources

- `aws_iam_role.lambda`: execution role trusted by `lambda.amazonaws.com`
- `aws_iam_role_policy.logs`: `logs:CreateLogStream` and `logs:PutLogEvents` on this function's log group only
- `aws_iam_role_policy.xray`: `xray:PutTraceSegments` and `xray:PutTelemetryRecords` on `*` (these actions have no resource-level permissions)
- `aws_cloudwatch_log_group.lambda`: `/aws/lambda/free-usage-xray-hello`, 7-day retention
- `aws_lambda_function.traced`: python3.12, 128 MB, 3 s timeout, tracing `Active`

All resources are tagged `Example = "xray-lambda-tracing"` and `ManagedBy = "Terraform"`.

## Always Free and cost notes

- X-Ray: the first 100,000 traces recorded and the first 1,000,000 traces retrieved or scanned each month are free ([CloudWatch pricing, X-Ray section](https://aws.amazon.com/cloudwatch/pricing/)). Each invoke records at most one trace. Past 100k, recording costs $0.000005 per trace.
- Lambda: 1,000,000 requests and 400,000 GB-s compute per month ([AWS Free Tier](https://aws.amazon.com/free/)). This example uses well under 15 GB-s.
- CloudWatch Logs: 5 GB ingestion and 5 GB archive per month ([AWS Free Tier](https://aws.amazon.com/free/)). Retention is 7 days.
- Scripts that call `get-trace-summaries` in a loop count against the 1M scanned limit.

### Sampling

Lambda samples 1 request per second plus 5% of additional requests, and this rate can't be changed ([Lambda and X-Ray docs](https://docs.aws.amazon.com/lambda/latest/dg/services-xray.html)). Lambda ignores custom sampling rules, so this example creates no `aws_xray_sampling_rule`. Invoking in a loop still traces 5% of the extra requests, so invoke by hand only.

### Do not enable

- Transaction Search or Application Signals: spans go to CloudWatch Logs (`aws/spans`), free for 3 months only, then billed per GB. Don't add an ADOT layer either.
- X-Ray Insights on a group: billed per trace, not covered by the free tier.
- KMS encryption config for X-Ray: account-wide, and adds KMS key and request costs. Keep the default AWS-owned encryption.

## Requirements

- Terraform installed
- AWS CLI configured with an IAM Identity Center profile
- Permissions to create/delete Lambda, IAM role/policy and CloudWatch log group resources, and to read X-Ray traces
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

1. Invoke the function 3 to 5 times by hand with the `invoke_command` output.
2. Wait about 30 seconds.
3. Open the CloudWatch console, X-Ray traces, then Trace map or Traces. Or run the `traces_command` output.
4. The first invoke shows an Init (cold start) subsegment; later warm invokes don't.

## Cleanup

```sh
terraform plan -destroy
terraform destroy
```

Then check:

- `aws lambda get-function --function-name free-usage-xray-hello` returns ResourceNotFound.
- The IAM role `free-usage-xray-hello-role` is gone.
- `aws logs describe-log-groups --log-group-name-prefix /aws/lambda/free-usage-xray-hello` is empty. If a late invoke recreated it, delete it by hand.
- `aws xray get-groups`, `aws xray get-sampling-rules` (only `Default`) and `aws xray get-encryption-config` (`Type: NONE`) show nothing created by this example.

Recorded traces can't be deleted. They expire after 30 days at no cost.
