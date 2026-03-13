locals {
  # Create a set of unique paths
  unique_paths = toset([for k, v in var.resource_paths : v.path_part])

  # Group methods by path
  paths_with_methods = {
    for path in local.unique_paths : path => {
      for method_key, config in var.resource_paths :
      config.http_method => {
        "x-amazon-apigateway-integration" = {
          uri                  = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${config.invocation.lambda_arn}/invocations"
          passthroughBehavior  = "when_no_match"
          httpMethod           = config.invocation.integration_http_method
          type                 = "AWS_PROXY"
          payloadFormatVersion = "2.0"
        }
        responses = {
          "default" = {
            description = "Default response"
          }
        }
        # Add security requirement to each method
        security = [
          {
            api_key = []
          }
        ]
      }
      if config.path_part == path
    }
  }

  openapi_spec = jsonencode({
    openapi = "3.0.1"
    info = {
      title   = var.api_name
      version = "1.0"
    }
    # Define security schemes
    components = {
      securitySchemes = {
        api_key = {
          type = "apiKey"
          name = "x-api-key"
          in   = "header"
        }
      }
    }
    # Apply security globally to all paths (optional, since we're adding it per method above)
    security = [
      {
        api_key = []
      }
    ]
    paths = {
      for path, methods in local.paths_with_methods : "/${path}" => methods
    }
  })
}

resource "aws_api_gateway_rest_api" "this" {
  name        = var.api_name
  description = var.api_description
  body        = local.openapi_spec

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_deployment" "this" {
  depends_on = [
    aws_api_gateway_rest_api.this
  ]

  rest_api_id = aws_api_gateway_rest_api.this.id
  description = "Deployment for ${var.api_name}"

  triggers = {
    redeployment = sha1(local.openapi_spec)
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.stage_name

  tags = var.tags
}

resource "aws_api_gateway_api_key" "api_key" {
  depends_on = [aws_api_gateway_deployment.this]
  name       = var.api_key_name
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  depends_on  = [aws_api_gateway_deployment.this]
  name        = "${var.api_name}-usage-plan"
  description = "API Usage Plan for ${var.api_name}"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = var.stage_name
  }

  throttle_settings {
    burst_limit = 200 # The maximum number of requests that clients can make in a given time period
    rate_limit  = 100 # The number of requests that clients can make per second
  }
}

resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  key_id        = aws_api_gateway_api_key.api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
}