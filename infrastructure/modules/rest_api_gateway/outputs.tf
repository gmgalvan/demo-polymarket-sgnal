output "api_gateway_invoke_url" {
  description = "The URL to invoke the API Gateway"
  value       = aws_api_gateway_stage.this.invoke_url
}

output "api_gateway_arn" {
  description = "The ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "api_gateway_id" {
  description = "The ID of the API Gateway"
  value       = aws_api_gateway_rest_api.this.id
}

output "api_gateway_stage_name" {
  description = "The name of the API Gateway stage"
  value       = aws_api_gateway_stage.this.stage_name
}