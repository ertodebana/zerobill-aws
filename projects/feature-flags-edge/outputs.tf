output "distribution_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "function_url" {
  description = "Calling this URL directly returns 403; only CloudFront's OAC can invoke it."
  value       = aws_lambda_function_url.origin.function_url
}

output "table_name" {
  value = aws_dynamodb_table.flags.name
}

output "table_arn" {
  value = aws_dynamodb_table.flags.arn
}

output "flags_url" {
  value = "https://${aws_cloudfront_distribution.this.domain_name}/flags/demo"
}

output "test_command" {
  value = "curl -si https://${aws_cloudfront_distribution.this.domain_name}/flags/demo | grep -iE '^(x-cache|age|cache-control)|\"flags\"'"
}

output "flip_flag_command" {
  value = "aws dynamodb update-item --region ${var.aws_region} --table-name ${aws_dynamodb_table.flags.name} --key '{\"app\":{\"S\":\"demo\"}}' --update-expression 'SET flags.#f = :v' --expression-attribute-names '{\"#f\":\"new_checkout\"}' --expression-attribute-values '{\":v\":{\"BOOL\":true}}'"
}

output "add_app_command" {
  value = "aws dynamodb put-item --region ${var.aws_region} --table-name ${aws_dynamodb_table.flags.name} --item '{\"app\":{\"S\":\"billing\"},\"flags\":{\"M\":{\"dark_mode\":{\"BOOL\":false}}}}'"
}

output "invalidate_command" {
  value = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.this.id} --paths \"/flags/demo\""
}
