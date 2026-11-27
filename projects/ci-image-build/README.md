# CI image build

This project uses CodeBuild to clone a public GitHub repository, build a container image, and push it to an ECR Public repository. CodeBuild's buildspec is stored in Terraform, so a commit in the source repository cannot replace the commands that run with the push role.

The default trigger is manual: run `aws codebuild start-build`. An optional EventBridge Scheduler can start one build every seven or more days; it is disabled by default. A CodeBuild state-change event sends an email when a build fails or times out.

## What it builds

- One ECR Public repository in `us-east-1`. Images and tags pushed to it are public.
- One CodeBuild project using the `BUILD_GENERAL1_SMALL` / `LINUX_CONTAINER` free-tier compute combination, privileged mode, a 10-minute build timeout, a 5-minute queue timeout, and at most one concurrent build.
- One CloudWatch log group with seven-day retention.
- A least-privilege CodeBuild role for its log group, ECR Public authorization, and image pushes to this repository.
- One SNS topic and email subscription, plus an EventBridge rule and target for failed or timed-out builds.
- Optional Scheduler resources when `schedule_expression` is set.

The default configuration creates **10 AWS resources** and one account-identity data source. The optional schedule adds three resources.

## Before you apply

1. Create a public GitHub repository that you control.
2. Copy `Containerfile.sample` into that repository as `Containerfile`, then commit it.
3. Set `github_repo_url` to that repository's HTTPS URL and `alert_email` to an address you can confirm.
4. Review the plan and confirm the ECR Public repository and image will be visible to everyone.

The GitHub repository must be public because CodeBuild clones it without credentials. Do not put secrets in the source repository or pass them as build arguments. The CodeBuild buildspec is the inline file in this Terraform module, not a file loaded from the GitHub repository.

After apply, click the SNS confirmation link. An unconfirmed subscription remains pending and AWS expires it after three days.

## Always Free and cost notes

The [AWS Free Tier page](https://aws.amazon.com/free/), [CodeBuild pricing](https://aws.amazon.com/codebuild/pricing/), [ECR pricing](https://aws.amazon.com/ecr/pricing/), [EventBridge pricing](https://aws.amazon.com/eventbridge/pricing/), [SNS pricing](https://aws.amazon.com/sns/pricing/), and [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/) were checked for the design on 2026-11-27. Recheck them before deployment; offers and account eligibility can change.

| Allowance | Free limit | Expected use |
| --- | --- | --- |
| CodeBuild on `general1.small` / `arm1.small` | 100 build minutes per month, shared across the account | About 2–4 minutes per small image build; roughly 20 builds may use about 60 minutes. Each build is rounded up to a full minute. |
| ECR Public storage | 50 GB | A tiny image should use only a few megabytes per unique digest. Old SHA tags can be removed manually. |
| ECR Public data transfer out | 500 GB/month for anonymous pulls or 5 TB/month for authenticated pulls | A few megabytes for this sample. Transfer above the allowance is billed to the downloader. |
| Scheduler invocations | 14 million per month | Zero by default; at most about five per month with the permitted weekly-or-slower schedule. |
| SNS publishes / email deliveries | 1 million / 1,000 per month | Only failed builds send email. |
| CloudWatch Logs ingestion and storage | 5 GB each per month | A few MB for small builds; logs expire after seven days. |
| AWS service events on the EventBridge default bus | Free | CodeBuild emits events when each build changes state. |

**The 100 CodeBuild minutes are the tightest limit and are shared with `examples/codebuild`.** A schedule must be at least seven days apart; daily builds would use most of the monthly allowance. Billing rounds each started minute up, and builds above the free allowance are billed. Larger compute types, GPU environments, fleets, webhooks that run on every push, and repeated build loops can cost more.

There is no paid dependency in the default design. It does not create CodePipeline, S3 artifact storage, private ECR, a VPC, NAT, public IPv4, a KMS key, or a custom EventBridge bus. Private ECR's offer is time-limited, so the project uses ECR Public. The default CodeBuild image is AWS's Amazon Linux 2023 x86_64 standard 5.0 image, listed in the [CodeBuild image reference](https://docs.aws.amazon.com/codebuild/latest/userguide/ec2-compute-images.html). For non-VPC builds, CodeBuild enables Docker by default; its docs say not to start `dockerd` manually when using a CodeBuild curated image ([Docker image guidance](https://docs.aws.amazon.com/codebuild/latest/userguide/create-project.html)).

The sample uses a base image from `public.ecr.aws/docker/library/`. Anonymous Docker Hub pulls from shared build IPs can be throttled and waste build minutes.

## Use

From this directory:

```sh
terraform init
terraform plan
terraform apply
```

Start a build and follow its logs:

```sh
aws codebuild start-build --project-name ci-image-build --region us-east-1
aws logs tail /aws/codebuild/ci-image-build --region us-east-1 --follow
```

To build a different branch or tag, pass an environment override:

```sh
aws codebuild start-build \
  --project-name ci-image-build \
  --region us-east-1 \
  --environment-variables-override name=GIT_REF,value=<branch-or-tag>,type=PLAINTEXT
```

Inspect the published image and run it with Podman:

```sh
aws ecr-public describe-images --region us-east-1 --repository-name ci-image-build
podman pull public.ecr.aws/<registry-alias>/ci-image-build:latest
podman run --rm public.ecr.aws/<registry-alias>/ci-image-build:latest
```

Use the repository URI from Terraform output instead of `<registry-alias>`. To estimate build-minute use, list project builds and inspect their start and end times:

```sh
aws codebuild list-builds-for-project --project-name ci-image-build --region us-east-1
aws codebuild batch-get-builds --ids <build-id> --region us-east-1 \
  --query 'builds[].[startTime,endTime,buildStatus]'
```

To exercise the failure notification, start a build with `GIT_REF` set to a branch that does not exist. The clone will fail, and the confirmed SNS subscriber should receive a message with the build name and a CloudWatch link. `TIMED_OUT` is also included in the EventBridge filter; that event status has not been verified in this module.

If you set `schedule_expression`, use only `rate(N days)` with N at least 7, for example `rate(7 days)`. The schedule starts builds until it is disabled or destroyed.

## Security and permissions

Privileged Docker builds can access the CodeBuild container's credentials. Build only repositories you control. The push role can publish images to this one ECR Public repository, and anything pushed is publicly readable. The inline buildspec keeps commits from changing the privileged build and push commands, but Dockerfile instructions still execute in the build container.

The Terraform operator needs permissions to create and delete the listed CodeBuild, ECR Public, CloudWatch Logs, EventBridge, SNS, IAM, and (if enabled) Scheduler resources. Scope resource-level actions to this project's names and ARNs where AWS supports it:

- CodeBuild: `CreateProject`, `UpdateProject`, `DeleteProject`, `BatchGetProjects`, `StartBuild`, `BatchGetBuilds`, `ListBuildsForProject`, and `StopBuild` on this project.
- IAM: create/read/delete the two roles and inline policies, plus `iam:PassRole` scoped to those role ARNs with `iam:PassedToService` set to `codebuild.amazonaws.com` or `scheduler.amazonaws.com` as appropriate.
- ECR Public: repository create/describe/delete, catalog-data read/write, `DescribeImages`, and `BatchDeleteImage` for cleanup. Starting a build uses the separate project role's ECR Public token and image-push permissions.
- CloudWatch Logs: create/delete the log group, set retention, read logs, and tag/list tags. The build role itself can create log streams and put events only in this group.
- EventBridge: `PutRule`, `PutTargets`, `RemoveTargets`, `DeleteRule`, and `DescribeRule` for the failure rule.
- SNS: create/delete/read the topic, set its policy, and create/list/delete its email subscription.
- Scheduler, only when enabled: create/update/delete/get/list the one schedule. Its role can only call `codebuild:StartBuild` on this project.

Starting a build needs `codebuild:StartBuild`; following logs needs CloudWatch Logs read actions. The scheduler role itself is limited to `codebuild:StartBuild` on this project.

Requirements: Terraform >= 1.5.0, AWS CLI v2, and Podman 4 or later for pulling and running the image. Read [HOWTO.md](../../HOWTO.md) before configuring AWS credentials.

## Cleanup

First make sure no build is still running:

```sh
aws codebuild list-builds-for-project --project-name ci-image-build --region us-east-1
aws codebuild batch-get-builds --ids <build-id> --region us-east-1 \
  --query 'builds[?buildStatus==`IN_PROGRESS`].id'
```

Stop any in-progress build before destroying the project. Then review and run the destroy from this directory:

```sh
terraform plan -destroy
terraform destroy
```

Check that the CodeBuild project, ECR Public repository, EventBridge rule, SNS topic, schedule (if enabled), log group, and IAM roles are gone. `force_destroy = true` lets Terraform remove the repository and its images. A late build may recreate the log group; delete it manually if it reappears. Remove local image copies and log out if you logged in:

```sh
podman rmi public.ecr.aws/<registry-alias>/ci-image-build:latest
podman logout public.ecr.aws
```

Review Billing and Free Tier usage after cleanup; usage records may be delayed.
