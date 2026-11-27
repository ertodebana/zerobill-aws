output "log_level_name" {
  value = aws_ssm_parameter.log_level.name
}

output "db_password_name" {
  value = aws_ssm_parameter.db_password.name
}

output "prefix" {
  value = var.prefix
}
