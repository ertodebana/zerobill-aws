output "schedule_name" {
  value = aws_scheduler_schedule.check.name
}

output "function_name" {
  value = aws_lambda_function.checker.function_name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.checker.name
}

output "table_name" {
  value = aws_dynamodb_table.checks.name
}

output "topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "alarm_names" {
  value = { for k, a in aws_cloudwatch_metric_alarm.down : var.urls[tonumber(k)] => a.alarm_name }
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.name_prefix}"
}

output "history_command" {
  value = "aws dynamodb query --table-name ${aws_dynamodb_table.checks.name} --key-condition-expression \"#u = :u\" --expression-attribute-names '{\"#u\":\"url\"}' --expression-attribute-values '{\":u\":{\"S\":\"${var.urls[0]}\"}}' --no-scan-index-forward --max-items 10 --region ${var.aws_region}"
}
