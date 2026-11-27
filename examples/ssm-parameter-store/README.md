# Systems Manager Parameter Store

Stores app config in a parameter hierarchy (`/ssm-demo/app/...`) and reads it back with the AWS CLI. You get one plain `String` parameter and one `SecureString` encrypted with the AWS-managed key `alias/aws/ssm`. No EC2 instances, no SSM agent, no IAM roles, no customer-managed KMS key.

Resources created:

- `aws_ssm_parameter.log_level`: `/ssm-demo/app/log-level`, `String`, tier `Standard`, value `info`
- `aws_ssm_parameter.db_password`: `/ssm-demo/app/db-password`, `SecureString`, tier `Standard`, dummy value, encrypted with `alias/aws/ssm`

## Always Free and cost notes

Sources: [AWS Free Tier](https://aws.amazon.com/free/), [Systems Manager pricing](https://aws.amazon.com/systems-manager/pricing/), [KMS pricing](https://aws.amazon.com/kms/pricing/).

- Standard parameters are free to store, and API interactions with them on standard throughput are free. The standard tier allows 10,000 parameters per account and Region and 4 KB per value. This example creates 2 small parameters.
- Every SecureString write and every `--with-decryption` read is a KMS request. KMS has a free tier of 20,000 requests/month across all Regions, shared with all your other KMS use. The AWS-managed key `aws/ssm` has no monthly key fee. Run reads by hand, not in a loop.
- **Advanced tier costs money** ($0.05 per parameter per month plus per-interaction charges) and **can't be downgraded**. You must delete the parameter to stop paying. Every parameter here sets `tier = "Standard"` explicitly.
- **Don't use Intelligent-Tiering or parameter policies** (expiration, notification). They upgrade or require the advanced tier. Also avoid the `aws:ec2:image` data type.
- **Don't enable higher throughput.** It is an account- and Region-wide setting, and once on, every interaction is billed, including standard ones.
- Don't set `key_id` to a customer-managed KMS key ($1/month per key).

## Requirements

- Terraform >= 1.5.0
- AWS CLI configured with an IAM Identity Center profile
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

### Pre-flight checks

These account and Region settings are outside Terraform. Check them before applying (replace `<region>` and `<account>`):

```sh
aws ssm get-service-setting --setting-id arn:aws:ssm:<region>:<account>:servicesetting/ssm/parameter-store/default-parameter-tier
# SettingValue should be Standard

aws ssm get-service-setting --setting-id arn:aws:ssm:<region>:<account>:servicesetting/ssm/parameter-store/high-throughput-enabled
# SettingValue should be false
```

If either differs, stop. Always pass `--tier Standard` on CLI writes.

### Required IAM permissions

- On `arn:aws:ssm:<region>:<account>:parameter/ssm-demo/*`: `ssm:PutParameter`, `ssm:GetParameter`, `ssm:GetParameters`, `ssm:GetParametersByPath`, `ssm:GetParameterHistory`, `ssm:DeleteParameter`, `ssm:AddTagsToResource`, `ssm:RemoveTagsFromResource`, `ssm:ListTagsForResource`
- On `*`: `ssm:DescribeParameters`
- Pre-flight checks only: `ssm:GetServiceSetting` on `arn:aws:ssm:<region>:<account>:servicesetting/ssm/parameter-store/*`
- KMS: the `aws/ssm` key policy normally lets account principals use it through SSM, so no IAM KMS statement should be needed. If decryption is denied, add `kms:Decrypt` and `kms:Encrypt` on the `aws/ssm` key ARN with the condition `kms:ViaService = ssm.<region>.amazonaws.com`.

## Security note

The SecureString value is stored **in plaintext** in the local `terraform.tfstate`. Use only the dummy default (`change-me-demo-only`), never a real secret, and don't commit the state file.

Upgrade path: the write-only argument `value_wo` (Terraform 1.11 or later) keeps the value out of state. Or create the secret out of band with `aws ssm put-parameter --type SecureString --tier Standard` and don't manage it in Terraform.

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Then explore with the CLI:

```sh
# 1. Plain String
aws ssm get-parameter --name /ssm-demo/app/log-level

# 2. SecureString without decryption: the value is ciphertext
aws ssm get-parameter --name /ssm-demo/app/db-password

# 3. With decryption: the value is plaintext (one KMS request)
aws ssm get-parameter --name /ssm-demo/app/db-password --with-decryption

# 4. Whole tree
aws ssm get-parameters-by-path --path /ssm-demo/app --with-decryption

# 5. Overwrite and see versions 1 and 2
aws ssm put-parameter --name /ssm-demo/app/log-level --value debug --type String --tier Standard --overwrite
aws ssm get-parameter-history --name /ssm-demo/app/log-level

# 6. Drift
terraform plan

# 7. Confirm both are Standard
aws ssm describe-parameters --parameter-filters Key=Name,Option=BeginsWith,Values=/ssm-demo --query 'Parameters[].[Name,Tier]'
```

In step 6, `terraform plan` wants to set `log-level` back to `info`. If Terraform and people both edit the same parameter, they fight. Pick one owner per parameter.

## Cleanup

```sh
terraform plan -destroy
terraform destroy
aws ssm describe-parameters --parameter-filters Key=Name,Option=BeginsWith,Values=/ssm-demo
# Parameters should be an empty list
terraform state list
# should print nothing
```

- The `alias/aws/ssm` key remains. It is AWS-managed, can't be deleted and has no monthly fee. That is expected.
- Rerun the pre-flight checks: the settings should still be `Standard` and `false`.
- Billing > Free Tier: KMS requests should be well under 20,000, with no Systems Manager charges.
- Delete the local `terraform.tfstate*` files, since they held the dummy secret.
