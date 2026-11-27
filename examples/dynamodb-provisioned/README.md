# DynamoDB provisioned table

Creates one DynamoDB table using provisioned throughput. This example demonstrates a small bounded table configuration; it is not a guarantee of zero charges.

## Always Free and cost notes

AWS currently lists DynamoDB among Always Free offers. Check the [current DynamoDB offer](https://aws.amazon.com/dynamodb/pricing/) and the Free Tier console for your account and region before deployment. Provisioned read/write capacity, storage, backups, streams, replicas, exports and other features have separate limits or charges. This example intentionally disables point-in-time recovery and streams.

## Requirements

- Terraform installed
- AWS CLI configured with an IAM Identity Center profile
- Permissions to create and delete a DynamoDB table
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Inspect the plan and confirm the selected account and region before applying. The table name can be changed with `-var='table_name=your-unique-name'`.

## Cleanup

```sh
terraform plan -destroy
terraform destroy
```

Confirm the table is deleted in the DynamoDB console. If you changed the example to enable backups or other features, clean those up separately.
