# Daily digest

This project sends a daily email summarizing worldwide earthquakes of magnitude 2.5 or higher. EventBridge Scheduler starts a Step Functions **Standard** workflow at 06:00 UTC. One Python Lambda calls the keyless USGS catalog API; Step Functions reads and writes the small DynamoDB history table directly and publishes the result through SNS.

## What it creates

- One Lambda function (`daily-digest-summarize`) and a log group with seven-day retention.
- One DynamoDB table with 1 RCU and 1 WCU, a report-date key, and TTL retention.
- One Standard state machine with logging and X-Ray tracing off.
- One SNS topic and email subscription.
- One EventBridge Scheduler schedule and its least-privilege role.

The table uses DynamoDB's default AWS-owned encryption key. This avoids KMS requests; there is deliberately no `server_side_encryption` block. The workflow has no S3, VPC, NAT, API Gateway, customer-managed KMS key, alarm, dashboard, or custom metric.

## Data source

The Lambda queries the [USGS FDSN Event Web Service](https://earthquake.usgs.gov/fdsnws/event/1/). It needs no API key, and USGS earthquake data is public domain. USGS recommends its real-time feeds for automated apps; this learner example makes one bounded calendar-day query per run. The email credits the USGS Earthquake Hazards Program. Keep that credit if you adapt the example.

## Always Free and cost notes

Always Free allowances are shared across your whole AWS account and region. Check current offers and your account usage before applying.

| Resource or usage | Free allowance | Expected use here |
| --- | --- | --- |
| Step Functions Standard | 4,000 transitions/month | About 155 on a 31-day happy path; up to about 250 with bounded retries |
| EventBridge Scheduler | 14 million invocations/month | 31 per month |
| Lambda | 1 million requests and 400,000 GB-seconds/month | 31 to 93 requests including retries; 128 MB, 15 seconds maximum |
| DynamoDB provisioned capacity | 25 RCU and 25 WCU per region | 1 RCU and 1 WCU |
| SNS email | 1,000 deliveries/month | 31 digest messages in a 31-day month, plus any failure notices |
| CloudWatch Logs | 5 GB ingestion and 5 GB storage/month | A few KB per run; seven-day retention |

The Step Functions limit is the tightest one. Every state transition and retry counts. This schedule is limited to one run a day; hourly runs would use about 3,600 transitions before counting the other Step Functions examples in the account. Keep backfills to a few days by hand. The workflow uses Standard, not the paid Express type. No SMS or customer-managed KMS key is used.

The SNS email subscription remains `PendingConfirmation` until you click the confirmation link. AWS expires unconfirmed subscriptions after three days; Terraform cannot delete a pending subscription.

## Requirements and permissions

Use Terraform 1.5 or newer, AWS provider 5.x, and an AWS CLI profile with permission to create and delete the resources listed above. Terraform needs IAM role and `iam:PassRole` permissions, Lambda, DynamoDB table and TTL permissions, SNS, Step Functions, EventBridge Scheduler, and CloudWatch Logs permissions. Do not use root credentials.

## Use

1. Set `alert_email` to an address you can confirm. Keep the default UTC schedule, or provide a cron expression with one fixed minute and hour; the validation rejects hourly and `rate()` schedules.
2. From this directory, run `terraform init`, `terraform fmt -check`, `terraform validate`, and inspect `terraform plan`.
3. After applying the reviewed plan, click the SNS email confirmation link.
4. Run the `run_now_command` output. It summarizes yesterday in UTC. On the first run, the subject says no previous day was stored.
5. Use `backfill_command` with the day before, then run the current day again to see the count comparison. Do not script a large backfill.
6. The next scheduled email arrives at 06:00 UTC. Set `schedule_state = "DISABLED"` to pause it.

The workflow calls USGS once per run, bounds the response to 5 MB, and returns a compact summary to Step Functions. Its Lambda role can only write to its own log group. The Step Functions role can invoke that Lambda, read/write the one table, and publish to the one topic. The Scheduler role can only start this state machine.

## Retention

DynamoDB TTL uses `expires_at` in Unix epoch seconds. Expired items are removed asynchronously, usually within a few days, without using write capacity. An expired record can still be read while deletion is pending; the one-day comparison remains harmless during that delay.

## Cleanup

From this directory and the same AWS account/profile, review `terraform plan -destroy`, then run `terraform destroy` when you are ready. Check that the schedule is gone first so it cannot keep starting a deleted state machine. Also check Step Functions, Lambda, DynamoDB, SNS, CloudWatch Logs, IAM, and `terraform state list`. A pending email subscription can remain for up to three days at no cost.
