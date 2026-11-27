# SNS fan-out to SQS

Shows the SNS pub/sub model with no compute. You publish a message to a Standard SNS topic from the CLI, then read it from an SQS queue subscribed to that topic.

Resources created:

1. `aws_sns_topic.this`: Standard topic. No FIFO, no encryption, no delivery-status logging.
2. `aws_sqs_queue.this`: Standard queue with SSE-SQS (no KMS key), 1-day retention, 10 s long polling, no DLQ.
3. `aws_sqs_queue_policy.this`: lets only `sns.amazonaws.com` call `sqs:SendMessage`, and only when `aws:SourceArn` is this topic. SNS can't deliver to SQS without it.
4. `aws_sns_topic_subscription.sqs`: `sqs` protocol with raw message delivery on.
5. Optional: `aws_sns_topic_subscription.email`, created only if `email_endpoint` is set.

## Always Free and cost notes

Sources: [AWS Free Tier](https://aws.amazon.com/free/) and [Amazon SNS pricing](https://aws.amazon.com/sns/pricing/). Offers change, so check both pages before you apply.

| Dimension | Always Free limit | This example |
|---|---|---|
| SNS publishes | 1,000,000/month. Each 64 KB chunk of payload counts as 1 publish | < 100 small publishes |
| SNS deliveries to SQS | Not charged per message | < 100 |
| SNS to SQS data transfer | Billed at internet data-transfer-out rates, covered by the 100 GB/month Always Free data transfer out (aggregated across services and regions) | < 1 MB |
| SNS HTTP/S deliveries | 100,000/month | 0 |
| SNS email deliveries | 1,000/month | 0 unless `email_endpoint` is set |
| SQS requests | 1,000,000/month | < 500 |

Free usage is counted monthly across all regions and does not roll over.

Cost risks this example avoids:

- No SMS or mobile push. SMS has no Always Free allowance.
- No FIFO topic or queue. They are billed differently.
- No KMS. A customer-managed key costs about $1/month. The queue uses free SSE-SQS and the topic is unencrypted.
- No delivery-status logging, which would need an IAM role and write CloudWatch Logs.
- Topic and queue are in the same region.

Keep messages short, because every 64 KB counts as one publish. Use one-off CLI calls. Don't publish or poll in a loop.

## Requirements

- Terraform >= 1.5.0
- AWS CLI configured with an IAM Identity Center profile
- Permissions to create/delete SNS topics and subscriptions, and SQS queues and queue attributes (including the queue policy)
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Publish a message, then receive it. The outputs print both commands ready to run:

```sh
$(terraform output -raw publish_command)
$(terraform output -raw receive_command)
```

With raw delivery on, the message `Body` is just `hello`. Delete it with the `ReceiptHandle` from the receive output:

```sh
aws sqs delete-message --queue-url "$(terraform output -raw queue_url)" \
  --receipt-handle '<ReceiptHandle>' --region us-east-1
```

To see the SNS JSON envelope (`Type`, `MessageId`, `TopicArn`, `Message`, signature fields), set `raw_message_delivery = false` in `main.tf`, apply, then publish and receive again.

Optional email subscription: `terraform apply -var 'email_endpoint=you@example.com'`, then click the link in the confirmation email. Terraform can't delete a pending (unconfirmed) email subscription. AWS removes it after 3 days, and it costs nothing.

## Cleanup

```sh
terraform plan -destroy
terraform destroy
```

Then check:

- `aws sns list-topics --region <region>` shows no `sns-fanout-demo` topic.
- `aws sns list-subscriptions --region <region>` shows no subscriptions for that topic. A `PendingConfirmation` email subscription expires by itself.
- `aws sqs list-queues --queue-name-prefix sns-fanout-demo --region <region>` returns nothing. Deletion can take up to 60 s to show.
- No CloudWatch log groups named `sns/<region>/...` (delivery logging was never on).
- Billing > Free Tier shows SNS and SQS usage well under the limits.
