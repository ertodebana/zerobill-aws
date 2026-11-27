# Aurora DSQL cluster

Creates one single-Region Amazon Aurora DSQL cluster (`aws_dsql_cluster.this`), a serverless, PostgreSQL-compatible database. You connect from your own machine with `psql` over the public endpoint `<identifier>.dsql.<region>.on.aws`. There is no password: a short-lived IAM auth token is the password.

Resources created: one `aws_dsql_cluster` with deletion protection off and an AWS-owned KMS key. No VPC, subnets, security groups, VPC endpoint, IAM role, customer-managed KMS key or AWS Backup plan.

## Always Free and cost notes

AWS lists Aurora DSQL on the [AWS Free Tier page](https://aws.amazon.com/free/). Per the [Aurora DSQL pricing page](https://aws.amazon.com/rds/aurora/dsql/pricing/), your first **100,000 DPUs and 1 GB of storage each month** are free. Above that you pay per DPU and per GB-month. With AWS Organizations the allowance applies per management account, and it is shared with all other Aurora DSQL use in the account.

An idle cluster has no instance or hourly charge and uses no DPUs, so it costs nothing. Auth tokens are signed locally by the CLI and cost nothing. This demo uses well under 1,000 DPUs and under 1 MB of storage.

Warnings:

- **Bulk loads and load tests.** Do not run `generate_series` inserts of millions of rows or benchmark loops. They can use up the 100,000 DPUs and push storage past 1 GB. Keep the demo to a handful of rows.
- **Leaving data behind.** Storage is billed per GB-month while the cluster exists. Destroy when done.
- **Multi-Region.** Do not add `multi_region_properties` or `aws_dsql_cluster_peering`. Replicated writes use extra DPUs and storage is billed in every Region.
- **Customer-managed KMS key.** Costs $1/month plus requests. This example uses `AWS_OWNED_KMS_KEY`.
- **AWS Backup.** Backups and restores are billed by AWS Backup. This example creates no backup plan; a plan made in the console would cost money.
- **VPC endpoint (PrivateLink).** Connecting from inside a VPC through an interface endpoint is paid. This example uses the public endpoint instead.

## Requirements

- Terraform 1.5.0 or newer
- `psql` 14 or newer (the endpoint needs TLS SNI)
- AWS CLI v2, recent enough to have `aws dsql`, configured with an IAM Identity Center profile
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials
- IAM permissions (**verify against the [Service Authorization Reference for Aurora DSQL](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonauroradsql.html)**; this list was not confirmed):
  - On `arn:aws:dsql:<region>:<account>:cluster/*`: `dsql:CreateCluster`, `dsql:GetCluster`, `dsql:UpdateCluster`, `dsql:DeleteCluster`, `dsql:TagResource`, `dsql:UntagResource`, `dsql:ListTagsForResource`, `dsql:DbConnectAdmin`
  - On `*`: `dsql:ListClusters`
  - `iam:CreateServiceLinkedRole` with condition `iam:AWSServiceName = dsql.amazonaws.com`, only the first time DSQL is used in the account

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Create and delete can take a few minutes (the provider timeout is 30 minutes).

Connect (replace `us-east-1` if you changed `aws_region`):

```sh
export PGHOST=$(terraform output -raw endpoint)
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --hostname "$PGHOST" --region us-east-1 --expires-in 3600)
PGSSLMODE=require psql --dbname postgres --username admin
```

Then in `psql`:

```sql
CREATE TABLE notes (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), body text);
INSERT INTO notes (body) VALUES ('hello'),('world');
SELECT * FROM notes;
```

Notes on DSQL behavior:

- The token expires (here after 1 hour). Regenerate it to reconnect.
- DSQL uses optimistic concurrency. A conflicting transaction can fail with a serialization error and must be retried.
- Some PostgreSQL features are not supported, such as foreign keys, sequences/`SERIAL` and triggers. That is why the example uses a `uuid` key. See [Unsupported PostgreSQL features in Aurora DSQL](https://docs.aws.amazon.com/aurora-dsql/latest/userguide/working-with-postgresql-compatibility-unsupported-features.html).

## Cleanup

```sh
terraform plan -destroy
terraform destroy
```

Deletion protection is off, so destroy works without edits. If it fails with a deletion-protection error, the setting was changed outside Terraform: run `terraform apply` to set it back to `false`, then destroy.

Then check:

- `aws dsql list-clusters --region us-east-1` does not list the identifier (`DELETING` is fine; it disappears shortly after).
- `terraform state list` is empty.
- `aws backup list-recovery-points-by-resource --resource-arn <cluster_arn>` is empty or returns not found.
- Billing > Free Tier: Aurora DSQL DPUs well under 100,000 and storage under 1 GB for the month.
