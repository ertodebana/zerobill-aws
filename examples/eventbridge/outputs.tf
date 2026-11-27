output "schedule_name" {
  value = aws_scheduler_schedule.tick.name
}

output "function_name" {
  value = aws_lambda_function.target.function_name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.target.name
}
