# Amazon Managed Service for Prometheus (AMP)

Creates a managed Prometheus backend with no AWS compute. You run a stock Prometheus locally in podman. It scrapes only itself and sends a filtered handful of series to the workspace over SigV4 `remote_write`. Then you query the workspace with PromQL through `awscurl`.

Resources created:

1. `aws_prometheus_workspace.demo`: alias `amp-demo`, AWS-owned encryption key (no customer KMS key), no vended CloudWatch logging.
2. `aws_prometheus_workspace_configuration.demo`: retention `retention_days` (default 7, down from the 150-day service default; allowed 1 to 30 here).
3. `aws_iam_policy.amp_demo`: `amp-demo-remote-write-query`, allows only `aps:RemoteWrite`, `aps:QueryMetrics`, `aps:GetSeries`, `aps:GetLabels` and `aps:GetMetricMetadata` on this workspace. **Terraform does not attach it.** You attach it to the user or role you run the demo as.

**No AWS compute is created**: no EKS, EC2, NAT, VPC endpoint, managed scraper, rule groups or alert manager. The only compute is a local container on your machine.

## Always Free and cost notes

Source: [Amazon Managed Service for Prometheus pricing, Free Tier section](https://aws.amazon.com/prometheus/pricing/) (checked 2026-11-27). AMP is listed as Always Free in the AWS Free Tier directory, but the pricing page only says "As part of the AWS Free Tier" and doesn't say whether the offer is Always Free or 12-month. **Confirm your account's classification under Billing > Free Tier in the console before relying on it.** Offers change; recheck before applying.

| Dimension | Free limit / month | This example |
|---|---|---|
| Metric samples ingested | 40 M | ~5 series x 1 sample/60 s = 7,200/day, so **~216 k/month even if left running 24/7** (about 0.5% of the limit) |
| Query samples processed | 200 B | A few dozen instant/range queries over 5 series: well under 1 M |
| Metrics stored | 10 GB | KB to low MB, capped by 7-day retention |
| Collector (managed scraper) | **No free allowance** ($0.04/collector-hour + $0.03/10 M samples) | 0, not used |

- **Don't remove the `write_relabel_configs` keep rule.** Prometheus self-scrape exposes several hundred series. With no filter at the default 15 s interval, that is about 1,000 series x 4/min x 43,200 min/month ≈ **170 M samples/month**, over 4x the free 40 M. Overage is billed per sample ingested. Estimate any change with: **series x samples/min x 43,200 = samples/month**.
- **Don't add targets or exporters** (node_exporter etc.), and don't lower `scrape_interval` below 60 s. Both multiply samples.
- **Don't add rule groups or an alert manager.** Recording and alerting rules run queries continuously, which count toward query samples processed.
- **Don't create a managed collector** (`aws_prometheus_scraper`). It has no free allowance and needs EKS anyway.
- Optional paid features are off: no customer-managed KMS key, no vended logging, no VPC/interface endpoint.
- **The limits are per account.** Other AMP workspaces in the account share the 40 M / 200 B / 10 GB.
- Stop the container when done. Usage is bounded even 24/7, but there is no reason to leave it running.

## Requirements

- Terraform >= 1.5.0. `aws_prometheus_workspace_configuration` needs a recent 5.x AWS provider (checked with v5.100.0); run `terraform init -upgrade` if an old 5.x is cached.
- AWS CLI v2 configured with an IAM Identity Center profile
- [podman](https://podman.io/) (this repo uses podman, not Docker)
- `awscurl`: `pipx install awscurl`
- The principal you run the demo as needs the `iam_policy_arn` output attached, or must already have those `aps:` actions on the workspace.
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

Least-privilege operator policy for Terraform itself (replace `REGION` and `ACCOUNT_ID`; names assume the default `name_prefix`). `aps:CreateWorkspace` doesn't support resource-level permissions, so it needs `"Resource": "*"`. `iam:TagPolicy`/`iam:UntagPolicy` are needed because the provider applies `default_tags` to the IAM policy.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CreateWorkspace",
      "Effect": "Allow",
      "Action": "aps:CreateWorkspace",
      "Resource": "*"
    },
    {
      "Sid": "ManageWorkspace",
      "Effect": "Allow",
      "Action": [
        "aps:DeleteWorkspace",
        "aps:DescribeWorkspace",
        "aps:UpdateWorkspaceAlias",
        "aps:DescribeWorkspaceConfiguration",
        "aps:UpdateWorkspaceConfiguration",
        "aps:TagResource",
        "aps:UntagResource",
        "aps:ListTagsForResource"
      ],
      "Resource": "arn:aws:aps:REGION:ACCOUNT_ID:workspace/*"
    },
    {
      "Sid": "ManageDemoPolicy",
      "Effect": "Allow",
      "Action": [
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:TagPolicy",
        "iam:UntagPolicy"
      ],
      "Resource": "arn:aws:iam::ACCOUNT_ID:policy/amp-demo-*"
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

Attach the `iam_policy_arn` output to your demo principal (or skip this if it already has the actions). Then try it:

```sh
# 1. Save the rendered Prometheus config (remote_write URL, SigV4 region, keep rule)
terraform output -raw prometheus_config > prometheus.yml

# 2. Export temporary credentials from your CLI profile into this shell
eval "$(aws configure export-credentials --format env)"

# 3. Start Prometheus locally (pinned tag)
podman run -d --name amp-demo-prom --network host \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN \
  -v "$PWD/prometheus.yml:/etc/prometheus/prometheus.yml:ro,Z" \
  docker.io/prom/prometheus:v3.5.0

# 4. Wait 2 to 3 minutes, then run an instant query. Expect up{job="prometheus"} 1
awscurl --service aps --region us-east-1 "$(terraform output -raw query_url)?query=up"

# 5. Range query: last 5 minutes, one point per 60 s
awscurl --service aps --region us-east-1 \
  "$(terraform output -raw prometheus_endpoint)api/v1/query_range?query=up&start=$(( $(date +%s) - 300 ))&end=$(date +%s)&step=60"

# 6. Check remote-write health
podman logs amp-demo-prom | grep -i remote
```

Use your `aws_region` in place of `us-east-1` if you changed it. Temporary credentials expire. If remote writes start failing with 403, rerun step 2 and recreate the container (`podman rm -f amp-demo-prom`, then step 3).

## Cleanup

```sh
podman rm -f amp-demo-prom
rm prometheus.yml
# Detach the policy first if you attached it; destroy fails while it is attached, e.g.:
# aws iam detach-user-policy --user-name <user> --policy-arn "$(terraform output -raw iam_policy_arn)"
# aws iam detach-role-policy --role-name <role> --policy-arn "$(terraform output -raw iam_policy_arn)"
terraform plan -destroy
terraform destroy
```

Check that nothing remains:

- `aws amp list-workspaces --alias amp-demo` returns an empty `workspaces` list (`DELETING` for a short while is normal).
- `aws iam list-policies --scope Local --query "Policies[?starts_with(PolicyName,'amp-demo')]"` returns `[]`.
- `podman ps -a --filter name=amp-demo-prom` shows nothing.
- `aws amp list-scrapers` is empty (this example never creates one).

Stored samples are deleted with the workspace, so no storage charge remains.
