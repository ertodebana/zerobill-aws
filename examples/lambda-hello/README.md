# Lambda hello

Creates a minimal Lambda function and a CloudWatch log group with finite retention. It demonstrates a serverless function without adding an API Gateway, VPC, load balancer, or other supporting services.

## Always Free and cost notes

AWS lists Lambda with an Always Free monthly usage offer. Check [current Lambda pricing and offer details](https://aws.amazon.com/lambda/pricing/) for account eligibility, request and duration limits, architecture and region details. CloudWatch Logs has separate ingestion and storage pricing; setting retention limits stored log history but does not eliminate ingestion charges. The function's actual invocations and duration matter.

## Requirements

- Terraform installed
- AWS CLI configured with an IAM Identity Center profile
- Permissions to create/delete Lambda, IAM role/policy, and CloudWatch log group resources
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Review the IAM policy and planned resources before applying. Invoke only for learning; repeated or large events can exceed free usage.

## Cleanup

```sh
terraform plan -destroy
terraform destroy
```

Check Lambda, IAM and CloudWatch in the console for remaining resources.
