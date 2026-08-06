data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket  = var.eks_state_bucket
    key     = var.eks_state_key
    region  = var.eks_state_region
    encrypt = true
  }
}

locals {
  cluster_name    = data.terraform_remote_state.eks.outputs.cluster_name
  hosted_zone_arn = "arn:aws:route53:::hostedzone/${var.hosted_zone_id}"

  tags = {
    Project   = "demo-polymarket-signal"
    Layer     = "lv-3-cluster-services"
    Component = "external-dns"
    ManagedBy = "terraform"
  }
}

module "irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.6.1"

  name            = "${local.cluster_name}-external-dns"
  use_name_prefix = false
  policy_name     = "${local.cluster_name}-ExternalDNSPolicy"

  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = [local.hosted_zone_arn]

  oidc_providers = {
    eks = {
      provider_arn = data.terraform_remote_state.eks.outputs.cluster_oidc_provider_arn
      namespace_service_accounts = [
        "${var.namespace}:${var.service_account_name}"
      ]
    }
  }

  tags = local.tags
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.chart_version
  namespace  = var.namespace

  cleanup_on_fail = true
  timeout         = 600
  wait            = true

  values = [
    yamlencode({
      provider = {
        name = "aws"
      }

      sources       = ["ingress"]
      domainFilters = [var.domain_filter]
      policy        = var.dns_policy
      registry      = "txt"
      txtOwnerId    = local.cluster_name

      annotationFilter = "external-dns.alpha.kubernetes.io/hostname"

      extraArgs = {
        "aws-zone-type"  = "public"
        "zone-id-filter" = var.hosted_zone_id
      }

      env = [
        {
          name  = "AWS_DEFAULT_REGION"
          value = var.aws_region
        }
      ]

      replicaCount = 1
      nodeSelector = var.node_selector

      serviceAccount = {
        create = true
        name   = var.service_account_name
        annotations = {
          "eks.amazonaws.com/role-arn" = module.irsa.arn
        }
      }

      podLabels = {
        "app.kubernetes.io/part-of" = "cluster-networking"
      }
    })
  ]
}
