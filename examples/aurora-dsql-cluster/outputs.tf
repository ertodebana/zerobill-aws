output "cluster_identifier" {
  value = aws_dsql_cluster.this.identifier
}

output "cluster_arn" {
  value = aws_dsql_cluster.this.arn
}

output "endpoint" {
  value = "${aws_dsql_cluster.this.identifier}.dsql.${var.aws_region}.on.aws"
}
