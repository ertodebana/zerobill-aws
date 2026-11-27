variable "aws_region" {
  description = "AWS region for the example. Verify the offer is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "function_name" {
  description = "Name for this Lambda function and its log group."
  type        = string
  default     = "free-usage-hello"
}
