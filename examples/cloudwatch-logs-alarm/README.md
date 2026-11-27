# CloudWatch logs to alarm

Shows the core CloudWatch loop with no compute: you write log lines from the CLI, a metric filter turns lines containing `ERROR` into a custom metric, an alarm changes state when that metric reaches 1, and a dashboard graphs both.

Resources created:

1. `aws_cloudwatch_log_group.demo`: `/2dollaraws/cloudwatch-demo`, STANDARD class, 1-day retention, no KMS key.
2. `aws_cloudwatch_log_stream.demo`: stream `manual`, so you can call `put-log-events` directly.
3. `aws_cloudwatch_log_metric_filter.errors`: pattern `"ERROR"` to metric `TwoDollarAws/CloudWatchDemo` / `ErrorCount`, no dimensions.
4. `aws_cloudwatch_metric_alarm.errors`: `cloudwatch-demo-errors`, standard resolution, Sum over 300 s >= 1, no actions.
5. `aws_cloudwatch_dashboard.demo`: `cloudwatch-demo`, one metric widget and one alarm widget.

No IAM roles are created because nothing runs inside AWS.

## Always Free and cost notes

Source: [Amazon CloudWatch pricing, free tier section](https://aws.amazon.com/cloudwatch/pricing/) (checked 2026-11-27). Offers change; recheck before applying.

| Dimension | Always Free limit | This example |
|---|---|---|
| Custom metrics | 10 (custom + detailed monitoring) | 1 (`ErrorCount`) |
| Alarms | 10 standard-resolution alarm metrics that list metrics directly, not Metrics Insights | 1 |
| Dashboards | 3 custom, up to 50 metrics each | 1 dashboard, 1 metric |
| Logs | 5 GB covering ingestion, archive storage and Logs Insights scans combined | KB-scale: a few dozen manual lines |
| API requests | 1M, **excluding GetMetricData, GetInsightRuleReport and GetMetricWidgetImage (always charged)** | Some hundred PutLogEvents/Describe calls |
| Live Tail | 1,800 min/month | 0 unless you try it |

- **The limits are per account, not per example.** If other stacks already use CloudWatch alarms, custom metrics or dashboards, this example's 1 + 1 + 1 can push you over.
- **GetMetricData is never free.** Use `get-metric-statistics` (counted in the free 1M requests) or the console, not `get-metric-data` in scripts. The pricing page does not say clearly whether console dashboard views are billed; with 1 metric the worst case is fractions of a cent.
- **Don't script log loops.** Piping large files or looping `put-log-events` can exceed 5 GB ($0.50/GB beyond). Retention is 1 day (`log_retention_days`, allowed 1, 3, 5, 7).
- **Keep the alarm plain.** High-resolution alarms (period < 60 s), anomaly detection, composite and Metrics Insights alarms are not free.
- **Don't add dimensions to the metric filter.** Each unique dimension set is a separate custom metric ($0.30/month each beyond 10).
- Not used: metric streams, Contributor Insights, Synthetics, scheduled Logs Insights queries, KMS on the log group.

## Requirements

- Terraform >= 1.5.0
- AWS CLI configured with an IAM Identity Center profile
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

Least-privilege operator policy (replace `REGION` and `ACCOUNT_ID`; names assume the default `name_prefix`). `Describe*`, `GetMetricStatistics` and `ListDashboards` don't support resource-level permissions, so they need `"Resource": "*"`.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LogGroup",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:PutRetentionPolicy",
        "logs:CreateLogStream",
        "logs:DeleteLogStream",
        "logs:DescribeLogStreams",
        "logs:PutMetricFilter",
        "logs:DeleteMetricFilter",
        "logs:PutLogEvents",
        "logs:ListTagsForResource",
        "logs:TagResource"
      ],
      "Resource": [
        "arn:aws:logs:REGION:ACCOUNT_ID:log-group:/2dollaraws/cloudwatch-demo",
        "arn:aws:logs:REGION:ACCOUNT_ID:log-group:/2dollaraws/cloudwatch-demo:*"
      ]
    },
    {
      "Sid": "AlarmAndDashboard",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:ListTagsForResource",
        "cloudwatch:TagResource",
        "cloudwatch:PutDashboard",
        "cloudwatch:GetDashboard",
        "cloudwatch:DeleteDashboards"
      ],
      "Resource": [
        "arn:aws:cloudwatch:REGION:ACCOUNT_ID:alarm:cloudwatch-demo-errors",
        "arn:aws:cloudwatch::ACCOUNT_ID:dashboard/cloudwatch-demo"
      ]
    },
    {
      "Sid": "ReadOnlyNoResourceLevel",
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeMetricFilters",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListDashboards"
      ],
      "Resource": "*"
    }
  ]
}
```

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

### Try it

Write one error line:

```sh
aws logs put-log-events \
  --log-group-name "$(terraform output -raw log_group_name)" \
  --log-stream-name manual \
  --log-events timestamp=$(date +%s000),message="ERROR boom"
```

Wait about 5 minutes, then check the alarm. It should report `ALARM`:

```sh
aws cloudwatch describe-alarms \
  --alarm-names "$(terraform output -raw alarm_name)" \
  --query 'MetricAlarms[0].StateValue'
```

Check the metric with `get-metric-statistics` (free requests), not `get-metric-data` (always charged):

```sh
aws cloudwatch get-metric-statistics \
  --namespace TwoDollarAws/CloudWatchDemo --metric-name ErrorCount \
  --statistics Sum --period 300 \
  --start-time "$(date -u -d '-30 min' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

(On macOS use `date -u -v-30M ...` for the start time.)

Open the dashboard: `terraform output -raw dashboard_url`.

## Cleanup

```sh
terraform plan -destroy
terraform destroy
```

Verify nothing is left:

```sh
aws logs describe-log-groups --log-group-name-prefix /2dollaraws/
aws cloudwatch describe-alarms --alarm-name-prefix cloudwatch-demo
aws cloudwatch list-dashboards --dashboard-name-prefix cloudwatch-demo
```

Destroying the log group also removes its stream and metric filter. The custom metric `TwoDollarAws/CloudWatchDemo ErrorCount` cannot be deleted. That's expected: it stops counting toward billing once no new data points arrive, and it drops out of `list-metrics` after about 2 weeks.
