output "order_url" {
  description = "Function URL that starts an order execution."
  value       = aws_lambda_function_url.place_order.function_url
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.saga.arn
}

output "orders_table" {
  value = aws_dynamodb_table.orders.name
}

output "inventory_table" {
  value = aws_dynamodb_table.inventory.name
}

output "topic_arn" {
  value = aws_sns_topic.notifications.arn
}

# The x-amz-security-token header in this command applies only to temporary credentials.
output "curl_example" {
  description = "SigV4 request for temporary or long-term credentials."
  value       = "curl --aws-sigv4 \"aws:amz:${var.aws_region}:lambda\" --user \"$AWS_ACCESS_KEY_ID:$AWS_SECRET_ACCESS_KEY\" -H \"x-amz-security-token: $AWS_SESSION_TOKEN\" -H 'content-type: application/json' -d '{\"orderId\":\"o-1\",\"sku\":\"SKU-RED\",\"qty\":1,\"amountCents\":1999}' ${aws_lambda_function_url.place_order.function_url}"
}
