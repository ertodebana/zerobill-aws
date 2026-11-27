# AWS account and safe CLI workflow

This guide gets a beginner from account creation to safely inspecting and deploying a small Terraform example. AWS screens and offers can change; follow the current AWS pages linked below when labels differ.

## Before you begin

- [ ] Read the example's README and list every resource it creates.
- [ ] Confirm that the service has an **Always Free** offer that applies to your account, region and usage. Do not rely on credits or trials.
- [ ] Decide whether you are comfortable with a paid AWS account. AWS's Free plan has account and duration restrictions and may close the account when its plan ends; it is not a permanent substitute for checking Always Free limits.
- [ ] Have a unique email address, a strong password, and a payment method if AWS requests one for identity verification.
- [ ] Install Terraform and AWS CLI v2 from their official download pages.

## 1. Create an AWS account

1. Go to [Create an AWS account](https://portal.aws.amazon.com/billing/signup) and follow the current sign-up flow.
2. Use an email address you control long term. The email becomes the root-user sign-in identifier.
3. Provide the requested contact, payment and identity verification information. Requirements can vary by location and account.
4. Choose the account plan that fits your use. This repository relies only on Always Free offers, but account plan restrictions still matter. Read [AWS Free Tier plans](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html) and [Free Tier FAQs](https://aws.amazon.com/free/free-tier-faqs/).
5. Finish phone verification and select the available support option.
6. Sign in to the [AWS Management Console](https://console.aws.amazon.com/) as **Root user** using the account email and password.

### Secure the root user

The root user has unrestricted account access. Use it only for tasks that require root.

- [ ] Enable MFA for the root user; use a passkey or authenticator/security key where supported.
- [ ] Save recovery codes or backup factors securely.
- [ ] Do not create root access keys.
- [ ] Do not use the root user for daily console or CLI work.
- [ ] Keep the root email and phone number current and protected.
- [ ] Turn on billing and Free Tier notifications in the billing console.

See [AWS root user best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/root-user-best-practices.html).

## 2. Set up a human identity and permissions

### Recommended: IAM Identity Center

IAM Identity Center provides human users temporary role credentials instead of long-lived IAM user keys. For a personal account, you can enable it in the AWS console and create a user and permission set. Store the Identity Center home/portal URL and its region; these are needed by the CLI setup.

1. In the console, open **IAM Identity Center** and enable it in a supported region.
2. Create a user for yourself and assign it to your AWS account.
3. Create or use a permission set with only the permissions required for the work. Avoid permanent administrator access; Terraform examples may require permissions to create and delete their listed resources.
4. Sign in through the Identity Center access portal, select the account and permission set, and confirm you can open the console.
5. For setup details, follow [Getting started with IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/getting-started.html).

### IAM users and access keys: use only when necessary

IAM users are identities inside one AWS account. For people, prefer Identity Center. Do not create an IAM user with administrator permissions and a permanent access key for convenience. Some tools or legacy workflows may require an IAM user's access key; in that case, grant only the needed permissions, enable MFA for console sign-in, rotate keys, and remove them when no longer needed. Never put keys in source control, Terraform files, shell history, or an agent prompt.

If an IAM user must use the CLI, AWS documents `aws configure` for local profiles. Enter keys only in the interactive prompt or a supported secure credential manager, and understand that the resulting key is long-lived until revoked. Follow [IAM security best practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html).

## 3. Install and sign in with AWS CLI

Install AWS CLI v2 using the [official installation guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html). Open a new terminal and confirm:

```sh
aws --version
```

Configure a named Identity Center profile:

```sh
aws configure sso --profile personal
```

Enter the portal start URL, Identity Center region, account, role/permission set, and a default workload region when prompted. Then log in and verify the identity:

```sh
aws sso login --profile personal
aws sts get-caller-identity --profile personal
```

Set the profile for commands in the current terminal:

```sh
export AWS_PROFILE=personal
aws sts get-caller-identity
```

PowerShell users can use `$env:AWS_PROFILE = "personal"`. When the session expires, run `aws sso login --profile personal` again. Sign out with `aws sso logout` when finished. See [AWS CLI IAM Identity Center configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html).

**Before every deployment**, verify `aws sts get-caller-identity` shows the intended account and identity. A configured profile can point to the wrong account.

## 4. Set up billing visibility

- [ ] In **Billing and Cost Management**, review the Free Tier page and current service usage.
- [ ] Configure Free Tier usage alerts and a budget alert to an email you read. Alerts notify; they do not necessarily stop resources or prevent charges.
- [ ] Learn where to see costs by service, region and usage type.
- [ ] Review the [AWS guide to tracking Free Tier usage](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/tracking-free-tier-usage.html) and [avoiding unexpected charges](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/avoid-charges-after-free-tier.html).

## 5. Run a Terraform example safely

Install Terraform from [HashiCorp's official guide](https://developer.hashicorp.com/terraform/install). Then from the chosen example directory:

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
```

Read the plan. Confirm the account, region, resource names, resource count, and cost risks. Terraform state may include sensitive values: keep it local for these examples, protect it, and do not commit it. If the example requires variables, copy its documented example file and never put secrets into a committed file.

Only after reviewing the plan should you apply:

```sh
terraform apply
```

Inspect the created resources in the AWS console. Avoid exposing endpoints or data publicly unless the example explicitly requires it and you understand the consequences.

## 6. Clean up

When done, return to the same directory and account/profile:

```sh
aws sts get-caller-identity
terraform plan -destroy
terraform destroy
```

Review the destroy plan before confirming. Then check the AWS console for remaining resources, including logs, backups, snapshots, storage, networking and detached resources. Check billing later as cost data can be delayed. Do not delete Terraform state until cleanup is confirmed; state helps Terraform track what it created.

## AWS Free usage limitations

- Always Free offers have service-specific monthly limits and exclusions; qualifying use does not make every related AWS resource free.
- Limits may apply across an account or region, and concurrent projects can consume the same allowance.
- Data transfer, logs, backups, snapshots, public IPs, NAT gateways, requests beyond quotas and optional features can add charges.
- AWS offers and account plans change. Recheck the official offer details at deployment time and read the service pricing page.
- Budgets and alerts are monitoring aids, not hard spending caps. Terraform destroy may not remove data or resources managed outside Terraform.
- A Free plan can have restrictions and a limited lifetime. This repository does not treat plan credits as proof that an example is free.

## Ready-to-deploy checklist

- [ ] I am signed in to the intended account with a non-root identity.
- [ ] MFA is enabled for privileged console access.
- [ ] I reviewed the current Always Free offer and its limits for this service and region.
- [ ] Billing alerts are enabled and I know they do not prevent charges.
- [ ] I reviewed all resources in `terraform plan` and understand possible charges.
- [ ] I know how to destroy the resources and verify cleanup.
- [ ] I have not placed credentials or secrets in the repository.

## Official references

- [AWS Free Tier](https://aws.amazon.com/free/)
- [AWS Free Tier plans](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier-plans.html)
- [AWS account sign-up](https://portal.aws.amazon.com/billing/signup)
- [IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html)
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-welcome.html)
- [Terraform AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
