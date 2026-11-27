# AWS Free Services, Used Well

> A practical, community-maintained collection of small Terraform examples for AWS services with **Always Free** usage offers.

[![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform)](https://developer.hashicorp.com/terraform)
[![AWS](https://img.shields.io/badge/Cloud-AWS-232F3E?logo=amazonaws)](https://aws.amazon.com/free/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

AWS free usage is useful for learning and small experiments, but it is not a promise that every deployment costs $0. Offers have monthly quotas, eligibility rules and exclusions. Check the live AWS offer and your account's billing console before deploying.

## Start here

1. Read [HOWTO.md](HOWTO.md) before creating an AWS account or configuring credentials.
2. Set up root-user security, a non-root operator, billing alerts and the AWS CLI.
3. Choose one example below, inspect its Terraform, and run `terraform plan` before applying.
4. Destroy resources when finished and confirm in the console that they are gone.

## Examples

| Example | What it demonstrates | Watch for |
| --- | --- | --- |
| [Aurora DSQL cluster](examples/aurora-dsql-cluster/) | A small single-Region Aurora DSQL cluster and IAM-authenticated PostgreSQL connection | Cluster hours and storage have limits; keep it single-Region and destroy it when finished. |
| [CloudFront with a Lambda URL](examples/cloudfront-lambda-url/) | A CloudFront distribution in front of a Lambda function URL using origin access control | Requests, data transfer and function calls share account allowances. |
| [CloudTrail event history](examples/cloudtrail-event-history/) | Inspect the free 90-day management event history without creating a trail | A trail adds S3 storage and request costs. |
| [CloudWatch logs and alarm](examples/cloudwatch-logs-alarm/) | Send log lines, turn matching lines into a metric, and alarm on that metric | Metrics, alarms, dashboards, log ingestion and retention share account limits. |
| [CodeBuild](examples/codebuild/) | A no-source build project with bounded compute and log retention | Build minutes are shared across projects; larger or GPU compute is paid. |
| [Cognito user pool](examples/cognito-user-pool/) | A Lite-tier user pool and public client for learner sign-in | Keep the tier explicit; SMS and custom domains can add charges. |
| [DynamoDB provisioned table](examples/dynamodb-provisioned/) | A small table with explicitly bounded provisioned capacity | Storage, backups, streams, replicas and excess requests can cost extra. |
| [ECR Public](examples/ecr-public/) | Publish a small container image to a public repository | Public image pulls consume transfer allowances; repository contents are public. |
| [EventBridge Scheduler](examples/eventbridge/) | A scheduled Lambda invocation with a least-privilege role | Keep schedules sparse and bound Lambda runtime and log retention. |
| [Lambda hello](examples/lambda-hello/) | A minimal function with a bounded CloudWatch log retention period | Requests, duration, networking, log ingestion and retained logs have separate limits or charges. |
| [Managed Prometheus](examples/managed-prometheus/) | A small scrape and query setup for Amazon Managed Service for Prometheus | Ingestion, storage and query dimensions have separate limits; avoid EKS or EC2 dependencies. |
| [SNS fanout to SQS](examples/sns-fanout-sqs/) | Deliver one topic's messages to a queue, with an optional email subscription | Email must be confirmed; KMS keys and SMS are excluded. |
| [SQS queue and DLQ](examples/sqs-queue-dlq/) | A standard queue with a dead-letter queue and redrive policy | Queue requests are shared; idle Lambda pollers can use requests too. |
| [Systems Manager Parameter Store](examples/ssm-parameter-store/) | Standard String and SecureString parameters using the AWS-managed key | SecureString values remain in Terraform state; customer-managed keys cost extra. |
| [Step Functions Standard](examples/step-functions-hello/) | A short workflow built from native states | Standard transitions are shared across the account; Express has no Always Free allowance. |
| [Simple Workflow Service](examples/swf-domain/) | Create an SWF domain and register workflow types with the AWS CLI | SWF domains cannot be deleted; destroy only deprecates a domain permanently. |
| [X-Ray Lambda tracing](examples/xray-lambda-tracing/) | Enable active tracing on a small Lambda function | Trace recording and retrieval have separate monthly limits. |

Examples are intentionally small and independent. They are starting points, not production architectures. Each folder contains its own README with prerequisites, resources, checks, and cleanup instructions.

## Projects

These projects combine multiple services to show complete learning paths. Each project has its own Terraform root and README. Review shared account quotas before deploying more than one at a time.

| Project | What it builds | Main watch-out |
| --- | --- | --- |
| [Uptime monitor](projects/uptime-monitor/) | Scheduled URL checks, alerts, status history and a dashboard | CloudWatch metrics and alarms are account-wide limits. |
| [Account cost guardrail](projects/account-cost-guardrail/) | Budget emails and an automatic lock on a dedicated sandbox role | Keep the Terraform operator outside the role the brake can lock. |
| [Notes API with Cognito auth](projects/notes-api-auth/) | A per-user notes API that verifies Cognito tokens in Lambda | Public function URLs can receive unauthenticated traffic; JWT checks happen before database access. This project uses AWS provider 6.28+. |
| [Order saga](projects/order-saga/) | Order intake, stock reservation, mock payment and compensation steps | Step Functions Standard transitions are shared across examples and projects. |
| [Webhook ingestion queue](projects/webhook-ingest-queue/) | Signed webhook intake, SQS buffering, idempotent processing and a DLQ alert | The worker is off by default because idle SQS polling uses free requests. This project uses AWS provider 6.28+. |
| [CI image build](projects/ci-image-build/) | CodeBuild builds a public container image and emails on failure | Build minutes are limited and shared; only build repositories you control. |
| [Feature flags at the edge](projects/feature-flags-edge/) | CloudFront caches flags from a protected Lambda URL backed by DynamoDB | CloudFront Function invocations are the tightest request limit. This project uses AWS provider 6.28+. |
| [Daily earthquake digest](projects/daily-digest/) | A daily USGS summary stored in DynamoDB and emailed through SNS | The daily cap protects the shared Step Functions transition allowance. |

## Guardrails

- This repository targets **Always Free offers only**. It does not depend on student or AWS Partner benefits, credits, or time-limited trials.
- “Always Free” means free within the current offer's limits and conditions, not unlimited use.
- AWS can change its offers. Confirm the service, region, usage dimensions and current limits on the [AWS Free Tier page](https://aws.amazon.com/free/) before each deployment.
- Terraform cannot guarantee a zero bill. Other resources, traffic, logs, data transfer, account settings, and usage outside the offer may be billed.
- Never commit credentials, account IDs that should be private, Terraform state, or `.tfvars` files containing secrets.
- Do not run `terraform apply` or `terraform destroy` until you have reviewed the plan and understand the impact.

## Use with a coding agent

Copy this prompt and replace the example path:

```text
You are helping me learn AWS using this public repository. Work only on `examples/REPLACE_ME`.

Before changing anything:
1. Read the example README and every Terraform file. Explain each resource, its purpose, and what can cost money.
2. Check the current AWS Always Free offer and its region, account, monthly quota, and exclusions. Do not count credits, trials, student benefits, or AWS Partner benefits as free.
3. Inspect the Terraform plan and identify resources or settings that could exceed an allowance or create charges.

Rules:
- Never ask me to paste credentials, put secrets in files, or use root credentials for Terraform.
- Do not run `terraform apply`, `terraform destroy`, or any command that changes AWS resources. Stop before those commands and ask me to review and explicitly approve the exact action.
- Do not widen IAM permissions or add paid services without explaining why and getting my approval.
- Prefer the smallest change, document it, and tell me how to validate and clean it up.
```

## Contributing

See [HOWTO.md](HOWTO.md) for the safety workflow. Contributions should use a separate example directory, pin or constrain provider versions, state every AWS resource created, identify cost drivers, and include a tested destroy path. A free-tier claim must link to an official AWS offer and state its relevant limits and assumptions.

## License

MIT. See [LICENSE](LICENSE).
