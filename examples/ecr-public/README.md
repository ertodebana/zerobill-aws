# ECR Public

Creates one public container repository (`aws_ecrpublic_repository`, default name `ecr-public-learning`) with minimal catalog data. You build a tiny busybox image locally with podman, push it to `public.ecr.aws/<alias>/ecr-public-learning`, then pull it again both authenticated and anonymously.

Resources created:

- `aws_ecrpublic_repository.this`, with `force_destroy = true` so `terraform destroy` also deletes pushed images.

There is no repository policy (the default allows public pull and owner-only push), no IAM role and no lifecycle policy (ECR Public doesn't support lifecycle policies).

The ECR Public control plane exists only in `us-east-1`, so `aws_region` is validated to be `us-east-1`. The images can still be pulled from anywhere in the world.

## Always Free and cost notes

Source: [Amazon ECR pricing](https://aws.amazon.com/ecr/pricing/) (checked 2026-11-27).

| Dimension | Always Free limit / month | Expected usage |
|---|---|---|
| Public repository storage (billed to the repo owner) | 50 GB | About 1-2 MB (one or two tags of a busybox-based image) |
| Data transfer out to the internet, anonymous pulls | 500 GB (rate-limited by source IP) | A few MB |
| Data transfer out to the internet, authenticated pulls | 5 TB | A few MB |
| Data transfer to AWS compute in any Region | Unlimited, free | None |
| Push (data transfer in) | Free | About 1-2 MB per push |

- **Who pays.** The repository owner pays for storage above 50 GB. Data transfer beyond the free allowances is billed to the AWS account that downloads, so strangers pulling your image cannot bill you. Anonymous pulls are rate-limited by source IP. Free usage does not roll over between months.
- **Pulling as the downloader.** When you pull *other* public images while logged in to `public.ecr.aws`, that transfer counts against your own 5 TB authenticated allowance.
- **No lifecycle policies.** ECR Public can't expire images automatically. Delete old tags yourself with `aws ecr-public batch-delete-image` (see Use). Keep images tiny and single-arch.
- **Private ECR is out of scope.** Private ECR (`aws_ecr_repository`, 500 MB) is a 12-month free tier offer, not Always Free. This example never creates it.
- **Public exposure.** Every layer, tag and catalog field is world-readable and listed in the [ECR Public Gallery](https://gallery.ecr.aws/). Put no secrets, internal hostnames or personal data in the image, the catalog data or the tags. Keep the random default registry alias rather than setting one that identifies you.

## Requirements

- Terraform >= 1.5.0
- podman 4+
- AWS CLI v2 configured with an IAM Identity Center profile
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

Least-privilege permissions. ECR Public repository ARNs have no region segment: `arn:aws:ecr-public::<account>:repository/ecr-public-learning`.

Terraform (on the repository ARN):

- `ecr-public:CreateRepository`, `ecr-public:DeleteRepository`, `ecr-public:DescribeRepositories`
- `ecr-public:PutRepositoryCatalogData`, `ecr-public:GetRepositoryCatalogData`
- `ecr-public:TagResource`, `ecr-public:UntagResource`, `ecr-public:ListTagsForResource`
- `ecr-public:GetRepositoryPolicy`
- `ecr-public:BatchDeleteImage` (used by `force_destroy`)

Push and walkthrough:

- On `*`: `ecr-public:GetAuthorizationToken`, `sts:GetServiceBearerToken`, `ecr-public:DescribeRegistries`
- On the repository ARN: `ecr-public:BatchCheckLayerAvailability`, `ecr-public:InitiateLayerUpload`, `ecr-public:UploadLayerPart`, `ecr-public:CompleteLayerUpload`, `ecr-public:PutImage`, `ecr-public:DescribeImages`

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Then, from this directory:

```sh
REPO=$(terraform output -raw repository_uri)

# Log in (token valid 12 hours)
aws ecr-public get-login-password --region us-east-1 | podman login --username AWS --password-stdin public.ecr.aws

# Build and check the size (about 1-2 MB)
podman build -t "$REPO:v1" .
podman image ls "$REPO"

# Push
podman push "$REPO:v1"

# Authenticated pull (counts against the 5 TB allowance)
podman rmi "$REPO:v1" && podman pull "$REPO:v1" && podman run --rm "$REPO:v1"

# Anonymous pull (counts against the 500 GB allowance, rate-limited by IP)
podman logout public.ecr.aws && podman pull "$REPO:v1"

# Inspect tags and sizes
aws ecr-public describe-images --region us-east-1 --repository-name ecr-public-learning --query 'imageDetails[].[imageTags,imageSizeInBytes]'

# Delete a tag
aws ecr-public batch-delete-image --region us-east-1 --repository-name ecr-public-learning --image-ids imageTag=v1
```

Beyond 500 GB/month anonymous or 5 TB/month authenticated, the downloader's account pays for transfer, not yours.

podman pushes OCI or Docker v2 manifests and ECR Public accepts both. Build without a `--platform` list so you push a single arch. Don't build a multi-arch manifest.

## Cleanup

```sh
terraform plan -destroy
terraform destroy
```

`force_destroy = true` deletes any pushed images along with the repository. Then check:

```sh
# Should return RepositoryNotFoundException
aws ecr-public describe-repositories --region us-east-1 --repository-names ecr-public-learning
# No leftover learning repos
aws ecr-public describe-repositories --region us-east-1
# Private ECR should be empty of anything from this example
aws ecr describe-repositories
# Should fail (the gallery listing may take a while to disappear)
podman pull "$REPO:v1"
# Local cleanup
podman rmi "$REPO:v1"
podman logout public.ecr.aws
# Should be empty
terraform state list
```

Billing > Free Tier should show ECR Public storage close to 0.
