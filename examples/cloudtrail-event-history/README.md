# CloudTrail event history digest

Every AWS account gets 90 days of CloudTrail management-event history per region, free and with no setup. This example shows how to query it, then deploys a small daily job (EventBridge Scheduler -> Lambda -> `LookupEvents`) that logs a digest of the last 24 hours of write (mutating) API calls to CloudWatch Logs.

Resources created:

- `aws_iam_role.lambda` and `aws_iam_role_policy.lambda`: the function role. It allows `cloudtrail:LookupEvents` on `*` (the action has no resource-level scoping) and log writes to the function's log group only.
- `aws_cloudwatch_log_group.lambda`: `/aws/lambda/cloudtrail-digest`, with 7-day retention.
- `aws_lambda_function.digest`: python3.12, 128 MB, 10 s timeout, no VPC.
- `aws_iam_role.scheduler` and `aws_iam_role_policy.scheduler`: lets Scheduler invoke only this function. The trust policy is limited to your account.
- `aws_scheduler_schedule.daily`: `rate(1 day)`, flexible window off, 0 retries.

No CloudTrail trail, S3 bucket, event data store or EventBridge rule is created.

## Zero-resource: event history alone

You get the free CloudTrail feature without deploying anything:

```sh
aws cloudtrail lookup-events --max-results 5 \
  --lookup-attributes AttributeKey=ReadOnly,AttributeValue=false
```

The Terraform in this directory only automates that query. Events appear in history about 5-15 minutes after the API call. History is per region, and IAM and console sign-in events land in `us-east-1`.

## Why no trail

A trail has to deliver to an S3 bucket, and S3 is not Always Free. The "one free management-events trail" covers only CloudTrail's delivery charge, not S3 storage and requests. EventBridge "AWS API Call via CloudTrail" rules also need an active trail, so a real-time alert version would bring the same S3 cost.

## Always Free and cost notes

| Dimension | Always Free limit | Expected usage | Source |
|---|---|---|---|
| CloudTrail event history | 90 days of management events; viewing, filtering and downloading are free | 1 `LookupEvents` call per day plus ad-hoc CLI calls | [AWS Free Tier](https://aws.amazon.com/free/), [CloudTrail pricing](https://aws.amazon.com/cloudtrail/pricing/) |
| CloudTrail trails | 1 free management-events copy per region | 0 trails created | [CloudTrail pricing](https://aws.amazon.com/cloudtrail/pricing/) |
| Lambda requests | 1,000,000 / month | ~31 / month | [AWS Free Tier](https://aws.amazon.com/free/) |
| Lambda compute | 400,000 GB-s / month | under 39 GB-s | [AWS Free Tier](https://aws.amazon.com/free/) |
| EventBridge Scheduler | 14,000,000 invocations / month | ~31 / month | [AWS Free Tier](https://aws.amazon.com/free/) |
| CloudWatch Logs | 5 GB ingest / 5 GB archive per month | well under 1 MB / month | [AWS Free Tier](https://aws.amazon.com/free/) |

Cost-relevant settings are bounded: log retention is 7 days, each run fetches one page of at most 50 events, the schedule must be a `rate(` or `cron(` expression, and Lambda retries are off. `LookupEvents` is throttled to 2 requests/s per account per region. If you add a trail, CloudTrail Lake or CloudWatch Logs delivery, you will be billed outside Always Free.

## Requirements

- Terraform installed
- AWS CLI configured with an IAM Identity Center profile
- Permissions to create and delete Lambda, IAM roles and policies, CloudWatch log groups and EventBridge Scheduler schedules, plus `cloudtrail:LookupEvents`
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Review the IAM policies and planned resources before you apply. To test without waiting for the schedule, run:

```sh
aws lambda invoke --function-name cloudtrail-digest out.json
aws logs tail /aws/lambda/cloudtrail-digest
```

Each event is one JSON line (`EventTime`, `EventName`, `EventSource`, `Username`), followed by a `{"count": N}` summary.

## Cleanup

```sh
terraform plan -destroy
terraform destroy
```

Then check that nothing is left:

```sh
aws lambda get-function --function-name cloudtrail-digest          # ResourceNotFoundException
aws scheduler get-schedule --name cloudtrail-digest-daily           # ResourceNotFoundException
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/cloudtrail-digest  # empty
aws iam get-role --role-name cloudtrail-digest-role                 # NoSuchEntity
aws iam get-role --role-name cloudtrail-digest-scheduler-role       # NoSuchEntity
aws cloudtrail describe-trails                                      # no trail from this example
```

If you invoked the function after destroy, Lambda can recreate the log group. Delete it if it is there. Event history stays on; you cannot disable it and it costs nothing.
