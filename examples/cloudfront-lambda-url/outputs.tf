output "distribution_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "function_url" {
  description = "Calling this directly returns 403, because only CloudFront (via OAC) may invoke it."
  value       = aws_lambda_function_url.origin.function_url
}

output "test_command" {
  value = "curl -sI https://${aws_cloudfront_distribution.this.domain_name}/ | grep -i -E 'x-cache|age|cache-control'"
}

output "invalidate_command" {
  value = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.this.id} --paths \"/*\""
}
