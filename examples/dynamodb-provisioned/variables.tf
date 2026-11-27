variable "aws_region" {
  description = "AWS region for the example. Verify the offer is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "table_name" {
  description = "Globally unique table name within this AWS account and region."
  type        = string
  default     = "free-usage-learning-table"
}
