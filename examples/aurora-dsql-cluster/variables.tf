variable "aws_region" {
  description = "AWS region for the example. Verify Aurora DSQL is available in your selected region."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Value of the Name tag. DSQL generates the cluster identifier itself."
  type        = string
  default     = "dsql-demo"
}
