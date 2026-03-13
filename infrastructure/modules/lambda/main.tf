resource "aws_lambda_function" "this" {
  function_name = var.function_name
  description   = var.description

  image_uri = var.docker_image_uri

  dynamic "image_config" {
    for_each = var.image_config != null ? [var.image_config] : []
    content {
      command           = var.image_config.command
      entry_point       = var.image_config.entry_point
      working_directory = var.image_config.working_directory
    }
  }

  role         = var.iam_lambda_role_arn
  package_type = "Image"
  timeout      = var.lambda_timeout
  memory_size  = var.lambda_memory_size

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [var.vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }

  ephemeral_storage {
    size = var.ephemeral_storage
  }

  environment {
    variables = var.environment_variables
  }

  # Lmabda code will be updated from CI/CD pipeline
  lifecycle {
    ignore_changes = [image_uri]
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${aws_lambda_function.this.function_name}"
  retention_in_days = var.log_retention_days
}

# Lambda permissions, what services can invoke this lambda.
resource "aws_lambda_permission" "this" {
  depends_on = [aws_lambda_function.this]
  for_each   = { for perm in var.invoke_permissions : perm.statement_id => perm }

  function_name = aws_lambda_function.this.function_name
  statement_id  = each.value.statement_id
  action        = "lambda:InvokeFunction"
  principal     = each.value.principal
  source_arn    = lookup(each.value, "source_arn", null)
}
