variable "aws_region" {
  description = "AWS region for the example. Verify the offer is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "queue_name" {
  description = "Name of the main queue. The DLQ is named <queue_name>-dlq."
  type        = string
  default     = "sqs-demo"
}
