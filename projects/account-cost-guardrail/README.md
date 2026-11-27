# Account cost guardrail

Budget alerts plus an automatic brake for a personal learning account. You get an email when **forecast** spend for the month goes over $1, a second, independent email when **actual** estimated charges go over $1, and the dedicated `cost-guardrail-sandbox` role is locked automatically (a `Deny *` policy is attached) if actual spend goes over $2. The identity you run Terraform with is never a target.

Deploy **one copy per account**. Run `aws budgets describe-budgets --account-id <acct>` first to see what you already have.

## What it builds

1. `data.aws_caller_identity.current`: account ID and the caller ARN for the lock-out precondition.
2. `aws_sns_topic.alerts` (`cost-guardrail-alerts`): Standard topic, no KMS.
3. `aws_sns_topic_policy.alerts`: lets `budgets.amazonaws.com` and `cloudwatch.amazonaws.com` publish, with `aws:SourceAccount` / `aws:SourceArn` conditions. It replaces the default topic policy.
4. `aws_sns_topic_subscription.email`: email to `var.alert_email`.
5. `aws_cloudwatch_metric_alarm.estimated_charges` (`cost-guardrail-estimated-charges`): `AWS/Billing EstimatedCharges`, Maximum over 6 h, > $1.
6. `aws_budgets_budget.this` (`cost-guardrail`): monthly COST budget, $2, credits and refunds excluded, notifications at FORECASTED > 50% and ACTUAL > 100%.
7. `aws_iam_role.sandbox` (`cost-guardrail-sandbox`): the experiment role and the only brake target.
8. `aws_iam_role_policy_attachment.sandbox`: one per `var.sandbox_policy_arns` (default `ReadOnlyAccess`).
9. `aws_iam_policy.brake` (`cost-guardrail-brake`): customer-managed `Deny *` on `*`.
10. `aws_iam_role.budgets_exec` (`cost-guardrail-budgets-exec`): assumed by `budgets.amazonaws.com`, with confused-deputy conditions.
11. `aws_iam_role_policy.budgets_exec`: inline, allows only `iam:AttachRolePolicy` / `iam:DetachRolePolicy` on the sandbox role, and only for the brake policy ARN.
12. `aws_budgets_budget_action.brake`: `APPLY_IAM_POLICY`, `AUTOMATIC` by default, at ACTUAL 100%, targets only the sandbox role.

No Lambda, log groups, S3, KMS key or VPC.

## Before you apply (manual, one time)

The billing metric does not exist until you opt in. Do this yourself, do not automate it:

1. Sign in as root or as an IAM identity with billing access.
2. Billing and Cost Management console, then **Billing Preferences**, then **Alert preferences**, **Edit**.
3. Tick **Receive CloudWatch Billing Alerts**, then **Save**.

Data appears in **us-east-1 only**, after about 15 minutes. Once enabled, the data collection cannot be turned off. That is free. Until then the alarm stays `INSUFFICIENT_DATA`. See [Create a billing alarm](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html).

## Always Free and cost notes

Sources, checked 2026-11-27: [AWS Budgets pricing](https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/), [AWS Free Tier](https://aws.amazon.com/free/), [Amazon SNS pricing](https://aws.amazon.com/sns/pricing/), [CloudWatch billing alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html).

| Dimension | Always Free limit | This project |
|---|---|---|
| Budget monitoring and notifications | Free | 1 budget, 2 notifications |
| Action-enabled budgets | First 2 per month free, then $0.10/day each | 1 |
| Budgets Reports | None free, $0.01 per report | 0 (not created) |
| CloudWatch alarms | 10 per account | 1 (standard resolution, 6 h period) |
| CloudWatch custom metrics | 10 | 0 (`AWS/Billing` is AWS-published) |
| CloudWatch API requests | 1M/month | Only Terraform's own calls |
| SNS publishes | 1M/month | Under 10/month |
| SNS email deliveries | 1,000/month | Under 10/month |
| IAM roles and policies | No charge | 2 roles, 1 managed policy, 1 inline policy |

Cost risks:

- **One copy per account.** A third action-enabled budget (a second copy under another `name`, or a hand-made budget with actions) costs $0.10/day.
- **No Budgets Reports.** They cost $0.01 each. This project creates none.
- **No CMK, no SMS.** Encrypting the topic with a customer managed KMS key costs $1/month and needs key-policy changes for Budgets. SMS has no free allowance. Email only.
- **Forecasts need history.** From the AWS Budgets best-practices docs: "AWS requires approximately 5 weeks of usage data to generate budget forecasts. If you set a budget to alert based on a forecasted amount, this budget alert isn't triggered until you have enough historical usage information." On a new account the forecast email may stay silent; the billing alarm (actual spend) is the backstop.
- **Credits are excluded** (`include_credit = false`) so the budget measures gross spend instead of hiding it.

## Safety model

This is **not a hard spending cap**. Billing data lags by hours, and the brake only restricts the sandbox role. Spend by the operator, or by resources that are already running, continues.

The brake can never lock out the operator, for four independent reasons:

1. **Only one target.** The budget action lists only the sandbox role, with no users or groups. The role name is fixed (`<name>-sandbox`) and created by this stack, so it can't be pointed at your admin role.
2. **A scoped execution role.** Even if someone edited the action by hand, the Budgets execution role can only attach or detach the brake policy, and only on the sandbox role. It does not use the account-wide AWS managed `AWSBudgetsActionsWithAWSResourceControlAccess` policy.
3. **A Terraform precondition.** Plan fails if you run Terraform while assumed into the sandbox role, with "Do not run Terraform as the sandbox role; the brake would lock Terraform out."
4. **The brake is a separate managed policy.** Budgets attaches and detaches it, so reversing the action restores the role exactly. Terraform never attaches it.

## Requirements

- Terraform >= 1.5.0 and the AWS CLI with an IAM Identity Center (or other non-root) profile. Review [HOWTO.md](../../HOWTO.md).
- Run as an admin or operator identity, **never** as the sandbox role.
- Permissions: `budgets:*Budget*` and `budgets:*BudgetAction*`; `iam:CreateRole`, `iam:CreatePolicy`, `iam:PutRolePolicy`, `iam:AttachRolePolicy` (plus the matching get/list/delete/detach calls), and `iam:PassRole` on the exec role; `sns:*` on the topic; `cloudwatch:PutMetricAlarm` and `cloudwatch:DeleteAlarms`.
- The billing-alerts toggle above.

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan -var alert_email=you@example.com
terraform apply -var alert_email=you@example.com
```

1. Click the confirmation link in the email from SNS. Until then nothing is delivered.
2. After the billing toggle, check the alarm leaves `INSUFFICIENT_DATA` (can take a few hours):
   `aws cloudwatch describe-alarms --alarm-names cost-guardrail-estimated-charges --region us-east-1`
3. Run experiments under the sandbox role: `terraform output -raw assume_sandbox_command`.
4. Check the brake: `terraform output -raw brake_status_command`.

### Test the brake without spending

You can't trigger a real $2 actual threshold on an Always Free account, and you shouldn't try. Simulate it instead, as the operator:

```sh
aws iam attach-role-policy --role-name cost-guardrail-sandbox \
  --policy-arn "$(terraform output -raw brake_policy_arn)"
# assume the sandbox role (assume_sandbox_command), export the credentials, then:
aws sts get-caller-identity   # still works, it can't be denied
aws s3 ls                     # AccessDenied
aws iam list-roles            # AccessDenied
# back as the operator:
aws iam detach-role-policy --role-name cost-guardrail-sandbox \
  --policy-arn "$(terraform output -raw brake_policy_arn)"
```

### Recovery

If the action fires, reverse it as the operator: `terraform output -raw reverse_brake_command`. Budgets detaches the policy. The action stays reversed for the rest of the period unless you choose **Reset** in the console.

## Cleanup

```sh
terraform plan -destroy -var alert_email=you@example.com
terraform destroy -var alert_email=you@example.com
```

Destroy order is handled for you: the budget action goes first, then the sandbox role (`force_detach_policies` removes the brake if Budgets still has it attached), then the brake policy.

Check afterwards:

- `aws budgets describe-budgets --account-id <acct>` doesn't list `cost-guardrail`, and `aws budgets describe-budget-actions-for-account --account-id <acct>` is empty.
- `aws iam get-role --role-name cost-guardrail-sandbox` and `aws iam get-role --role-name cost-guardrail-budgets-exec` return NoSuchEntity.
- `aws iam list-policies --scope Local --query "Policies[?PolicyName=='cost-guardrail-brake']"` is empty. If destroy hit a DeleteConflict, run `aws iam list-entities-for-policy --policy-arn <arn>`, detach, and destroy again.
- `aws cloudwatch describe-alarms --alarm-name-prefix cost-guardrail --region us-east-1` is empty.
- `aws sns list-topics --region us-east-1` has no `cost-guardrail-alerts`. A PendingConfirmation subscription may linger for up to 3 days at no cost.
- The billing-alerts toggle stays on. That is expected, free, and can't be undone.
- Billing console, Free Tier page: Budgets shows at most 1 action-enabled budget this month.
