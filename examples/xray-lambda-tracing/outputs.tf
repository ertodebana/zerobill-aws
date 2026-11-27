output "function_name" {
  value = aws_lambda_function.traced.function_name
}

output "invoke_command" {
  value = "aws lambda invoke --function-name ${aws_lambda_function.traced.function_name} --region ${var.aws_region} /dev/null"
}

output "traces_command" {
  value = "aws xray get-trace-summaries --start-time $(date -d '-10 min' +%s) --end-time $(date +%s) --region ${var.aws_region}"
}
