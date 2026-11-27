output "function_url" {
  description = "Public Lambda function URL. Keep it private and watch for unexpected traffic."
  value       = aws_lambda_function_url.api.function_url
}

output "user_pool_id" {
  description = "Cognito user pool ID."
  value       = aws_cognito_user_pool.this.id
}

output "client_id" {
  description = "Public Cognito app client ID."
  value       = aws_cognito_user_pool_client.this.id
}

output "table_name" {
  description = "Provisioned DynamoDB notes table name."
  value       = aws_dynamodb_table.notes.name
}

output "issuer" {
  description = "Cognito issuer expected in access tokens."
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.this.id}"
}
