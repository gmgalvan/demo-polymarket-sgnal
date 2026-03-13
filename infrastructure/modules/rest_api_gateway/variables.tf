variable "api_name" {
  description = "The name of the API Gateway"
  type        = string
}

variable "api_description" {
  description = "The description of the API Gateway"
  type        = string
}

variable "stage_name" {
  description = "The name of the API Gateway stage"
  type        = string
}

variable "lambda_invoke_arn" {
  description = "The ARN of the Lambda function to invoke"
  type        = string
}

variable "resource_paths" {
  description = "A map of resource paths and their corresponding HTTP methods and invocation configurations"
  type = map(object({
    path_part   = string
    parent_path = string
    http_method = string
    invocation = object({
      integration_http_method = string
      lambda_arn              = string
    })
  }))
  default = {}
}

variable "api_key_name" {
  description = "The name of the API Gateway API Key"
  type        = string

}

variable "tags" {
  description = "A map of tags to assign to the API Gateway resources"
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "The AWS region to deploy the API Gateway"
  type        = string

}