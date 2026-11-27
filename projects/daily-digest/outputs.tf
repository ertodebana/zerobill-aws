output "state_machine_arn" {
  description = "Step Functions Standard state machine ARN."
  value       = aws_sfn_state_machine.digest.arn
}

output "table_name" {
  description = "DynamoDB table holding daily summaries."
  value       = aws_dynamodb_table.days.name
}

output "topic_arn" {
  description = "SNS topic ARN for digest emails."
  value       = aws_sns_topic.digest.arn
}

output "schedule_name" {
  description = "EventBridge Scheduler schedule name."
  value       = aws_scheduler_schedule.daily.name
}

output "function_name" {
  description = "Lambda summarizer function name."
  value       = aws_lambda_function.summarize.function_name
}

output "log_group_name" {
  description = "CloudWatch Logs group with seven-day retention."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "run_now_command" {
  description = "Start a digest execution for yesterday in UTC."
  value       = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.digest.arn} --input '{}'"
}

output "backfill_command" {
  description = "Start a digest execution for a chosen UTC report date."
  value       = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.digest.arn} --input '{\"report_date\":\"YYYY-MM-DD\"}'"
}

output "read_history_command" {
  description = "Read the small retained history table."
  value       = "aws dynamodb scan --table-name ${aws_dynamodb_table.days.name} --max-items 40"
}
