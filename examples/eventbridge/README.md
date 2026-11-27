# EventBridge Scheduler invoking Lambda

Creates an EventBridge Scheduler schedule that runs a small Lambda function at a fixed rate (default `rate(1 hour)`). It shows the least-privilege IAM role the scheduler assumes to call its target. No custom event bus, `PutEvents`, Pipes, API destinations, archives or Schema Discovery are used.

Resources created:

- `aws_scheduler_schedule.tick`: schedule `eventbridge-demo-tick` in the `default` group, flexible window off, 0 retries.
- `aws_iam_role.scheduler` + `aws_iam_role_policy.invoke`: role `eventbridge-demo-scheduler-role`, trusted by `scheduler.amazonaws.com` from your account only, allowed only `lambda:InvokeFunction` on the one function.
- `aws_lambda_function.target`: `eventbridge-demo-target`, Python 3.12, 128 MB, 3 s timeout. It logs the event it receives.
- `aws_cloudwatch_log_group.target`: `/aws/lambda/eventbridge-demo-target`, 7-day retention.
- `aws_iam_role.lambda` + `aws_iam_role_policy.logs`: Lambda execution role, allowed only to write to that log group.

## Always Free and cost notes

Per [EventBridge pricing](https://aws.amazon.com/eventbridge/pricing/), EventBridge Scheduler includes **14,000,000 invocations per month** free. The allowance is monthly with no 12-month limit. The [Free Tier page](https://aws.amazon.com/free/) card for EventBridge shows a "Trial" label, but the item is tagged Always Free; the label is not a time limit. Check both pages before applying; offers change.

| Dimension | Always Free limit | This example |
|---|---|---|
| Scheduler invocations | 14,000,000/month | 720/month at `rate(1 hour)`, 8,640 at `rate(5 minutes)` |
| Lambda requests | 1,000,000/month | 720/month |
| Lambda compute | 400,000 GB-s/month | about 9 GB-s/month |
| CloudWatch Logs | 5 GB ingestion, 5 GB storage | under 1 MB/month |

- **Not free:** custom events (`PutEvents`, custom event buses) cost $1.00 per million events. Archive/replay, Pipes and API destinations have no free allowance. This example uses none of them.
- Sub-minute rates are rejected by variable validation. `rate(1 minute)` is 43,200/month, still free.
- Retries are set to 0 so a failing function cannot multiply invocations.
- Log retention is 7 days so logs do not pile up forever.

## Requirements

- Terraform installed
- AWS CLI configured with an IAM Identity Center profile
- Permissions to create/delete EventBridge Scheduler schedules, Lambda functions, IAM roles/policies (including `iam:PassRole` for the scheduler role) and CloudWatch log groups
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

The first run comes up to 1 hour after apply. Check it worked:

```sh
aws logs tail /aws/lambda/eventbridge-demo-target --since 2h
```

While testing, run more often (still free), then switch back:

```sh
terraform apply -var 'schedule_expression=rate(5 minutes)'
```

Pause the schedule without deleting anything:

```sh
terraform apply -var 'schedule_state=DISABLED'
```

## Cleanup

```sh
terraform plan -destroy
terraform destroy
```

Then check nothing is left:

```sh
aws scheduler list-schedules --name-prefix eventbridge-demo
aws lambda get-function --function-name eventbridge-demo-target        # expect ResourceNotFound
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/eventbridge-demo
aws iam get-role --role-name eventbridge-demo-scheduler-role           # expect NoSuchEntity
aws iam get-role --role-name eventbridge-demo-target-role              # expect NoSuchEntity
```

A late Lambda write can recreate the log group after destroy; if it shows up, delete it by hand. `function.zip` is build output and is gitignored; you can delete it.
