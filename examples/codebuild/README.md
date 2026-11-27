# CodeBuild

Creates one CodeBuild project with no source repository, no artifacts and no VPC. The buildspec is inline and only prints some details about the build container. You start a build from the CLI, watch its phases, read the logs in CloudWatch and check how many build minutes each run used.

Resources created:

- `aws_codebuild_project.this`: `codebuild-learning`. Source `NO_SOURCE` with an inline buildspec, `NO_ARTIFACTS`, `NO_CACHE`, `LINUX_CONTAINER` / `BUILD_GENERAL1_SMALL`, a 5-minute build timeout, a 5-minute queue timeout, 1 concurrent build at most, CloudWatch logs on and S3 logs off.
- `aws_cloudwatch_log_group.build`: `/aws/codebuild/codebuild-learning`, with 1-day retention.
- `aws_iam_role.codebuild`: `codebuild-learning-role`. Only `codebuild.amazonaws.com` in your own account (`aws:SourceAccount`) can assume it.
- `aws_iam_role_policy.codebuild_logs`: allows only `logs:CreateLogStream` and `logs:PutLogEvents` on that log group.

## Always Free and cost notes

The [AWS Free Tier page](https://aws.amazon.com/free/) and the [CodeBuild pricing page](https://aws.amazon.com/codebuild/pricing/) (both checked 2026-11-27) give **100 build minutes per month** on `general1.small` or `arm1.small`, for on-demand EC2 compute only. This allowance never expires and applies to new and existing accounts.

| Dimension | Always Free limit / month | Expected usage (about 10 builds) |
|---|---|---|
| CodeBuild build minutes, general1.small (shared with arm1.small) | 100 min | About 10-20 min. A trivial build takes 1-2 min including provisioning, and billing counts every started minute. |
| Worst case if a build hangs | n/a | 5 min, capped by `build_timeout` (for each build) |
| Concurrent builds | n/a | 1 (`concurrent_build_limit`) |
| CloudWatch Logs ingestion ([pricing](https://aws.amazon.com/cloudwatch/pricing/)) | 5 GB | Well under 1 MB |
| CloudWatch Logs storage | 5 GB | Well under 1 MB, and retention is 1 day |
| S3 / KMS / data transfer | n/a | None: no source, artifacts, cache or S3 logs. The default AWS-managed key costs nothing. |

- **Pinned compute type.** `compute_type = "BUILD_GENERAL1_SMALL"` with `type = "LINUX_CONTAINER"` is `general1.small` (x86_64, 2 vCPU, 4 GiB). Validation blocks reject any other value.
- **GPU trap.** `BUILD_GENERAL1_SMALL` combined with `LINUX_GPU_CONTAINER` is "Linux GPU Small", a paid GPU type, even though the compute type has the same name. That is why the environment type is pinned too.
- **Shared allowance.** The 100 minutes are shared between `general1.small` and `arm1.small`. Builds you run in other projects on either type count against the same budget.
- **Per-minute rounding.** A 61-second build counts as 2 minutes. Above the free tier, general1.small costs about $0.005 per minute.
- **Lambda compute** (`lambda.arm.1GB` / `lambda.x86-64.1GB`) has its own allowance of 6,000 build seconds per month. This example does not use it.
- **Not free:** medium or larger types, GPU types, reserved capacity fleets (they bill even when idle), Sandbox and the Docker image server. This example creates none of them.
- No webhooks, schedules or pipelines are created. The only way a build starts is when you run `start-build`.

## Requirements

- Terraform >= 1.5.0
- AWS CLI configured with an IAM Identity Center profile
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

Least-privilege policy for the learner. Replace `REGION` and `ACCOUNT` with your values. The action names were checked against the [Service Authorization Reference](https://docs.aws.amazon.com/service-authorization/latest/reference/reference_policies_actions-resources-contextkeys.html).

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CodeBuildProject",
      "Effect": "Allow",
      "Action": [
        "codebuild:CreateProject",
        "codebuild:UpdateProject",
        "codebuild:DeleteProject",
        "codebuild:BatchGetProjects",
        "codebuild:StartBuild",
        "codebuild:BatchGetBuilds",
        "codebuild:ListBuildsForProject",
        "codebuild:StopBuild"
      ],
      "Resource": "arn:aws:codebuild:REGION:ACCOUNT:project/codebuild-learning"
    },
    {
      "Sid": "ServiceRole",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:TagRole",
        "iam:PutRolePolicy",
        "iam:GetRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole"
      ],
      "Resource": "arn:aws:iam::ACCOUNT:role/codebuild-learning-role"
    },
    {
      "Sid": "PassRoleToCodeBuild",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::ACCOUNT:role/codebuild-learning-role",
      "Condition": { "StringEquals": { "iam:PassedToService": "codebuild.amazonaws.com" } }
    },
    {
      "Sid": "LogGroup",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:PutRetentionPolicy",
        "logs:TagResource",
        "logs:ListTagsForResource",
        "logs:GetLogEvents",
        "logs:FilterLogEvents",
        "logs:StartLiveTail"
      ],
      "Resource": [
        "arn:aws:logs:REGION:ACCOUNT:log-group:/aws/codebuild/codebuild-learning",
        "arn:aws:logs:REGION:ACCOUNT:log-group:/aws/codebuild/codebuild-learning:*"
      ]
    },
    {
      "Sid": "DescribeLogGroups",
      "Effect": "Allow",
      "Action": "logs:DescribeLogGroups",
      "Resource": "*"
    }
  ]
}
```

`logs:DescribeLogGroups` is a list action, so it can't be limited to one log group.

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Start a build and check its status and phase durations:

```sh
BUILD_ID=$(aws codebuild start-build --project-name codebuild-learning --query 'build.id' --output text)
aws codebuild batch-get-builds --ids "$BUILD_ID" \
  --query 'builds[0].[buildStatus,phases[].[phaseType,durationInSeconds]]'
```

Follow the logs:

```sh
aws logs tail /aws/codebuild/codebuild-learning --follow
```

See how long the build ran. Billing rounds each build up to the next whole minute:

```sh
aws codebuild batch-get-builds --ids "$BUILD_ID" \
  --query 'builds[0].[startTime,endTime]'
```

Count the builds you have run against the 100-minute budget:

```sh
aws codebuild list-builds-for-project --project-name codebuild-learning --query 'length(ids)'
```

## Cleanup

Before destroying, make sure no build is still running:

```sh
aws codebuild list-builds-for-project --project-name codebuild-learning --output text --query 'ids' \
  | xargs -n 100 aws codebuild batch-get-builds --query 'builds[?buildStatus==`IN_PROGRESS`].id' --ids
# Stop any build it lists:
aws codebuild stop-build --id <id>
```

Then destroy:

```sh
terraform plan -destroy
terraform destroy
```

Checks after destroy:

- `aws codebuild batch-get-projects --names codebuild-learning` lists it under `projectsNotFound`.
- `aws logs describe-log-groups --log-group-name-prefix /aws/codebuild/codebuild-learning` is empty. A late build did not recreate the group.
- `aws iam get-role --role-name codebuild-learning-role` returns `NoSuchEntity`.
- `aws codebuild list-fleets` is empty. This example creates no fleet.
- `terraform state list` is empty.
- Billing > Free Tier shows CodeBuild build minutes well under 100.
