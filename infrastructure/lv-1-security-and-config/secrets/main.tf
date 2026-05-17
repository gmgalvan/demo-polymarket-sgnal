locals {
  base_path = "${var.project_name}/${var.environment}"

  managed_secrets = {
    grafana = {
      name = "${local.base_path}/platform-observability/grafana"
      initial_payload = {
        password = var.initial_secret_placeholder
      }
    }
    langfuse = {
      name = "${local.base_path}/app-observability/langfuse"
      initial_payload = {
        postgres_password = var.initial_secret_placeholder
        nextauth_secret   = var.initial_secret_placeholder
        salt              = var.initial_secret_placeholder
      }
    }
  }

  external_secrets = {
    app_integrations = {
      name = "${local.base_path}/app-integrations/api-keys"
      initial_payload = {
        anthropic_api_key = var.initial_secret_placeholder
        tavily_api_key    = var.initial_secret_placeholder
      }
    }
    inference = {
      name = "${local.base_path}/inference/api-keys"
      initial_payload = {
        ngc_api_key         = var.initial_secret_placeholder
        huggingface_api_key = var.initial_secret_placeholder
      }
    }
  }

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
    },
    var.additional_tags,
  )
}

module "managed_secrets" {
  source = "../../modules/multiple-secrets-manager"

  secrets = local.managed_secrets
  tags    = local.common_tags
}

module "external_secrets" {
  source = "../../modules/multiple-secrets-manager"

  secrets = local.external_secrets
  tags    = local.common_tags
}

resource "aws_ssm_parameter" "config" {
  for_each = var.config_parameters

  name  = "/${local.base_path}/config/${each.key}"
  type  = "String"
  tier  = "Standard"
  value = each.value

  tags = merge(
    local.common_tags,
    {
      ConfigPurpose = each.key
    },
  )
}
