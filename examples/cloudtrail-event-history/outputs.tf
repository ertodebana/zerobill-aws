output "function_name" {
  value = aws_lambda_function.digest.function_name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.lambda.name
}

output "schedule_name" {
  value = aws_scheduler_schedule.daily.name
}
