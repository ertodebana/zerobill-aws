output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "budget_name" {
  value = aws_budgets_budget.this.name
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.estimated_charges.alarm_name
}

output "sandbox_role_arn" {
  value = aws_iam_role.sandbox.arn
}

output "brake_policy_arn" {
  value = aws_iam_policy.brake.arn
}

output "assume_sandbox_command" {
  value = "aws sts assume-role --role-arn ${aws_iam_role.sandbox.arn} --role-session-name experiment"
}

output "brake_status_command" {
  value = "aws budgets describe-budget-actions-for-budget --account-id ${local.account_id} --budget-name ${aws_budgets_budget.this.name}"
}

output "reverse_brake_command" {
  value = "aws budgets execute-budget-action --account-id ${local.account_id} --budget-name ${aws_budgets_budget.this.name} --action-id ${aws_budgets_budget_action.brake.action_id} --execution-type REVERSE_BUDGET_ACTION"
}
