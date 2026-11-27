output "log_group_name" {
  value = aws_cloudwatch_log_group.demo.name
}

output "log_stream_name" {
  value = aws_cloudwatch_log_stream.demo.name
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.errors.alarm_name
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.name_prefix}"
}
