variable "aws_region" {
  description = "AWS region for the example. Verify the offer is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "state_machine_name" {
  description = "Name for the state machine. The IAM role is named <name>-role."
  type        = string
  default     = "step-functions-hello"
}
