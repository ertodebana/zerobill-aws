# SQS queue with dead-letter queue

Creates a standard SQS queue and a dead-letter queue (DLQ). You send, receive and delete messages from the AWS CLI and watch long polling, the visibility timeout, and a message that fails 3 times move to the DLQ. No compute is involved.

Resources created:

- `aws_sqs_queue.dlq`: standard queue `sqs-demo-dlq`, SSE-SQS, 1-day retention, 20 s long polling.
- `aws_sqs_queue.main`: standard queue `sqs-demo`, SSE-SQS, 1-hour retention, 30 s visibility timeout, 20 s long polling, redrive to the DLQ after 3 receives.
- `aws_sqs_queue_redrive_allow_policy.dlq`: lets only `sqs-demo` use the DLQ.

## Always Free and cost notes

AWS lists SQS on the [Free Tier page](https://aws.amazon.com/free/). Per [SQS pricing](https://aws.amazon.com/sqs/pricing/), all customers get **1 million SQS requests per month** free, shared across all regions (except GovCloud) and all SQS use in the account. Check both pages before applying; offers change.

- Every SQS action counts as a request, including empty receives.
- Each 64 KB chunk of a payload is billed as 1 request. `max_message_size = 65536` keeps each message to 1 chunk.
- A batch call (1 to 10 messages) is 1 request, so batching saves requests.
- SSE-SQS encryption has no KMS charge. A customer-managed KMS key would cost $1/month plus KMS requests, so this example does not use one.
- **Do not leave a polling loop running.** One client long-polling at 20 s makes about 130,000 empty receives a month; ten clients exceed the free tier. Run receive commands by hand, not in a `while true` loop.
- **No Lambda consumer.** A Lambda event source mapping polls the queue continuously, even when idle, and those polls count as SQS requests. That is why it is left out.
- Only a standard queue is used. FIFO and fair queues are billed differently.

Expected usage for this example is under 1,000 requests.

## Requirements

- Terraform installed
- AWS CLI configured with an IAM Identity Center profile
- Review [HOWTO.md](../../HOWTO.md) before using AWS credentials
- IAM permissions on `arn:aws:sqs:<region>:<account>:sqs-demo*`:
  `sqs:CreateQueue`, `sqs:DeleteQueue`, `sqs:GetQueueAttributes`, `sqs:SetQueueAttributes`, `sqs:GetQueueUrl`, `sqs:TagQueue`, `sqs:UntagQueue`, `sqs:ListQueueTags`, `sqs:SendMessage`, `sqs:ReceiveMessage`, `sqs:DeleteMessage`
- `sqs:ListQueues` on `*`

## Use

```sh
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Send, receive and delete a message:

```sh
Q="$(terraform output -raw queue_url)"
aws sqs send-message --queue-url "$Q" --message-body hello
aws sqs receive-message --queue-url "$Q"
# copy ReceiptHandle from the output
aws sqs delete-message --queue-url "$Q" --receipt-handle '<ReceiptHandle>'
```

DLQ demo: send a message, then receive it three times without deleting it.

```sh
aws sqs send-message --queue-url "$Q" --message-body poison
aws sqs receive-message --queue-url "$Q" --visibility-timeout 0   # run 3 times
aws sqs receive-message --queue-url "$(terraform output -raw dlq_url)"
```

The message moves on the 4th receive attempt on the main queue, so you may need one more `receive-message` on `$Q` before it shows up in the DLQ.

## Cleanup

```sh
terraform plan -destroy
terraform destroy
terraform state list   # should print nothing
aws sqs list-queues --queue-name-prefix sqs-demo --region us-east-1   # should return no URLs
```

SQS blocks reusing a deleted queue name for 60 seconds, so wait before re-creating. Check the Billing > Free Tier page: SQS requests should be well under 1,000,000 for the month.
