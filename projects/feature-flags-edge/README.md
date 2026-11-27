# Feature flags at the edge

This project serves small, read-only feature flag documents from DynamoDB through a private Lambda function URL and CloudFront. CloudFront caches successful and unknown-app responses for a bounded period. A CloudFront Function lowercases valid app paths and rejects other paths before they reach the origin.

The public endpoint is `https://<distribution-domain>/flags/<app>`. The origin URL requires AWS IAM authentication; a direct request to the function URL should return 403.

## What it builds

1. A provisioned DynamoDB table with one read unit and one write unit, plus a seeded `demo` item.
2. A Lambda execution role and inline policy with access only to this function's log group and `dynamodb:GetItem` on the flags table.
3. A 7-day CloudWatch log group and a 128 MB Python 3.12 Lambda origin with a 3-second timeout.
4. An `AWS_IAM` Lambda function URL and the two Lambda permissions CloudFront OAC needs, scoped to the distribution.
5. A SigV4 CloudFront Origin Access Control, a custom path-only cache policy, and a viewer-request CloudFront Function.
6. A pay-as-you-go CloudFront distribution in `PriceClass_100`, using its default hostname and certificate. No flat-rate plan is attached.

The cache key contains only the normalized path. Query strings, headers and cookies do not create additional cache entries. Invalid paths return a generated 404 at the edge without invoking Lambda.

## Response

`GET /flags/demo` returns a document like:

```json
{"app":"demo","flags":{"new_checkout":false,"banner_text":"hello"},"generated_at":"2026-11-27T10:00:00Z"}
```

An unknown app returns `404 {"error":"unknown app"}`. Both responses are cached for `cache_ttl_seconds`; `generated_at` is the time the origin response was generated.

## Always Free and cost notes

The values below are the offer assumptions captured in the architecture note on 2026-11-27. Check the live offer and your account's Free Tier usage before deploying.

| Dimension | Always Free limit | This project at the design usage |
| --- | --- | --- |
| CloudFront requests | 10 million/month | About 432,000 for 10 clients polling once a minute |
| **CloudFront Function invocations** | **2 million/month** | About 432,000; this is the practical ceiling because the function runs on every viewer request, including cache hits |
| CloudFront data transfer out | 1 TB/month | About 0.2 GB at 0.5 KB per response |
| Lambda requests / compute | 1 million requests / 400,000 GB-seconds | At most about 260,000 requests and 3,250 GB-seconds under the conservative cache-location estimate |
| DynamoDB provisioned capacity | 25 RCU / 25 WCU per Region | 1 RCU / 1 WCU; table storage is expected to stay below 10 KB |
| CloudWatch Logs | 5 GB/month | Expected below 50 MB, with 7-day retention |
| CloudFront invalidation paths | 1,000/month | A few paths when an immediate refresh is needed |

Sources: [CloudFront pay-as-you-go pricing](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/), [DynamoDB provisioned pricing](https://aws.amazon.com/dynamodb/pricing/provisioned/), [Lambda pricing](https://aws.amazon.com/lambda/pricing/), and [AWS Free Tier](https://aws.amazon.com/free/).

**CloudFront Function invocations are the real request ceiling, not the 10 million request allowance.** Keep client polling at or below once a minute, and destroy the stack when done. Do not subscribe the distribution to a flat-rate plan. This endpoint is public and has no WAF; a deliberate flood can exceed the free limits. `distribution_enabled = false` pauses the distribution but does not delete it.

The response uses `max-age=0` and `s-maxage` for shared caching. CloudFront may use both edge and regional cache layers, so check the `Age` header and measure observed staleness. If the 60-second bound needs to be stricter, lower `cache_ttl_seconds` (for example, to 30 seconds).

The project leaves out CloudFront KeyValueStore (its management API is billed), Lambda@Edge, WAF, custom domain and certificate, Route 53, origin shield, logging, additional metrics, S3, API Gateway and customer-managed KMS keys. The DynamoDB table has no `server_side_encryption` block, so it uses the AWS-owned key and makes no KMS calls.

## Requirements and permissions

- Terraform 1.5 or later, AWS provider 6.28 or later (constrained below 7.0), and AWS credentials in the intended account. The provider is newer than the repo's usual 5.x constraint because `function_url_auth_type` is required to scope the Lambda URL permission to `AWS_IAM`; this project does not weaken that permission.
- Permissions to create/delete the listed CloudFront, Lambda, DynamoDB, IAM, and CloudWatch Logs resources, including `iam:PassRole` for the Lambda role.
- To edit flags manually, `dynamodb:UpdateItem` and `dynamodb:PutItem` on the table ARN output.
- Read [HOWTO.md](../../HOWTO.md) before configuring credentials or deploying.

## Use

From this directory, initialize Terraform, review the configuration and plan, and apply only after you understand the public endpoint and account-wide limits. CloudFront deployment can take several minutes.

1. Confirm the email/account profile and get the output values:

   ```sh
   terraform output
   ```

2. Call the `flags_url` output twice. The first response should show a cache miss; the next should show a cache hit and an `Age` header:

   ```sh
   terraform output -raw flags_url
   curl -si "$(terraform output -raw flags_url)"
   ```

3. Call the `function_url` output directly. It should return 403 because only CloudFront may invoke it:

   ```sh
   curl -i "$(terraform output -raw function_url)"
   ```

4. Request an invalid path such as `/wp-admin`. It should return an edge-generated 404 and create no Lambda log line.
5. Run the `flip_flag_command` output to change `new_checkout`, then request `/flags/demo` again. The old value may remain until the cache expires. For an immediate refresh, run `invalidate_command`.
6. Add another app with the `add_app_command` output. App keys must use lowercase `a-z`, digits, and hyphens, up to 64 characters.
7. Use the `test_command` output to compare cache headers. To count origin calls, inspect `/aws/lambda/feature-flags-edge-origin` in CloudWatch Logs.

The outputs also contain commands to add an app, flip a flag, and invalidate the cached path. Read them before running: they edit the table or invalidate the distribution.

## Pause and cleanup

Set `distribution_enabled = false` and apply to pause the public endpoint. To remove the stack, review the destroy plan and then destroy it. CloudFront disablement/deletion can take about 15 minutes.

After cleanup, confirm the distribution, function, DynamoDB table, Lambda log group, and IAM role are gone. A Lambda invocation during cleanup may recreate the log group, so check and remove it manually if needed. Confirm Billing has no flat-rate plan attached and CloudFront request/function usage remains below its account-wide limits.
