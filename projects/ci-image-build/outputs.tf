output "project_name" {
  description = "CodeBuild project name."
  value       = aws_codebuild_project.this.name
}

output "repository_uri" {
  description = "Public ECR repository URI."
  value       = aws_ecrpublic_repository.this.repository_uri
}

output "log_group_name" {
  description = "CloudWatch Logs group for build output."
  value       = aws_cloudwatch_log_group.build.name
}

output "sns_topic_arn" {
  description = "Topic used for build failure emails."
  value       = aws_sns_topic.alerts.arn
}

output "event_rule_name" {
  description = "EventBridge rule that matches failed or timed-out builds."
  value       = aws_cloudwatch_event_rule.build_failed.name
}

output "start_build_command" {
  description = "Start a manual build."
  value       = "aws codebuild start-build --project-name ${var.name} --region ${var.aws_region}"
}

output "pull_command" {
  description = "Pull the latest public image."
  value       = "podman pull ${aws_ecrpublic_repository.this.repository_uri}:latest"
}

output "schedule_name" {
  description = "Optional Scheduler schedule name, or null when scheduling is disabled."
  value       = var.schedule_expression == null ? null : aws_scheduler_schedule.weekly[0].name
}
