output "workspace_id" {
  value = aws_prometheus_workspace.demo.id
}

output "workspace_arn" {
  value = aws_prometheus_workspace.demo.arn
}

output "prometheus_endpoint" {
  value = aws_prometheus_workspace.demo.prometheus_endpoint
}

# prometheus_endpoint already ends in "/".
output "remote_write_url" {
  value = "${aws_prometheus_workspace.demo.prometheus_endpoint}api/v1/remote_write"
}

output "query_url" {
  value = "${aws_prometheus_workspace.demo.prometheus_endpoint}api/v1/query"
}

output "iam_policy_arn" {
  value = aws_iam_policy.amp_demo.arn
}

output "prometheus_config" {
  description = "Local Prometheus config. Save with: terraform output -raw prometheus_config > prometheus.yml"
  value = templatefile("${path.module}/prometheus.yml.tftpl", {
    remote_write_url = "${aws_prometheus_workspace.demo.prometheus_endpoint}api/v1/remote_write"
    region           = var.aws_region
  })
}
