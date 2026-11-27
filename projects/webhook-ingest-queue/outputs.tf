output "webhook_url" {
  description = "Public Lambda Function URL, protected by HMAC request signatures."
  value       = aws_lambda_function_url.ingest.function_url
}

output "queue_url" {
  value = aws_sqs_queue.main.id
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "table_name" {
  value = aws_dynamodb_table.events.name
}

output "secret_param_name" {
  value = aws_ssm_parameter.secret.name
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.dlq_depth.alarm_name
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.name}"
}

output "worker_enabled" {
  value = var.worker_enabled
}

output "worker_toggle_hint" {
  value = "terraform apply -var worker_enabled=true   # then false when done"
}
