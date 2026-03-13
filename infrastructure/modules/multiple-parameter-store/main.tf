provider "aws" {
  region = var.aws_region
}

locals {
  yaml_content = yamldecode(file(var.yaml_file))

  effective_environment = coalesce(var.environment, "general")

  # Extract cross-account sharing configuration
  cross_account_config = try(local.yaml_content.cross_account_sharing, {})
  enable_sharing       = try(local.cross_account_config.enabled, false)
  target_accounts      = try(local.cross_account_config.target_accounts, [])

  all_parameters = flatten([
    for domain, values in local.yaml_content : [
      for key, value_obj in try(values, {}) : {
        unique_key = "/${var.solution}/${var.tenant}/${local.effective_environment}/${domain}/${key}",
        name       = "/${var.solution}/${var.tenant}/${local.effective_environment}/${domain}/${key}",
        type       = try(value_obj.type, "String"),
        tier       = local.enable_sharing ? "Advanced" : try(value_obj.tier, "Standard"), # Force Advanced tier if sharing is enabled
        value      = value_obj.value
      }
    ]
    if domain != "aws_region" && domain != "project_name" && domain != "cross_account_sharing"
  ])

  # Create a map of parameter ARNs for RAM association
  parameter_arns = {
    for param in aws_ssm_parameter.parameters : param.name => param.arn
  }
}

resource "aws_ssm_parameter" "parameters" {
  for_each = { for param in local.all_parameters : param.unique_key => param }

  lifecycle {
    ignore_changes = [value]
  }

  name  = each.value.name
  type  = each.value.type
  tier  = each.value.tier
  value = each.value.value

  tags = {
    Environment = local.effective_environment
    Tenant      = var.tenant
    Solution    = var.solution
  }
}

# Conditional creation of RAM sharing resources
resource "aws_ram_resource_share" "parameter_share" {
  count = local.enable_sharing ? 1 : 0

  name                      = "${var.solution}-${var.tenant}-parameter-share"
  allow_external_principals = true

  tags = {
    Environment = local.effective_environment
    Tenant      = var.tenant
    Solution    = var.solution
  }
}

# Associate all parameters with the RAM share
resource "aws_ram_resource_association" "parameter_associations" {
  for_each = local.enable_sharing ? local.parameter_arns : {}

  resource_arn       = each.value
  resource_share_arn = aws_ram_resource_share.parameter_share[0].arn
}

# Share with target accounts
resource "aws_ram_principal_association" "account_sharing" {
  for_each = local.enable_sharing ? toset(local.target_accounts) : []

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.parameter_share[0].arn
}