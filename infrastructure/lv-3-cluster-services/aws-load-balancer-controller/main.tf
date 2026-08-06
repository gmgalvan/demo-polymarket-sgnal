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
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name

  tags = {
    Project   = "demo-polymarket-signal"
    Layer     = "lv-3-cluster-services"
    Component = "aws-load-balancer-controller"
    ManagedBy = "terraform"
  }
}

module "irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.6.1"

  name            = "${local.cluster_name}-aws-load-balancer-controller"
  use_name_prefix = false
  policy_name     = "${local.cluster_name}-AWSLoadBalancerControllerPolicy"

  attach_load_balancer_controller_policy = true

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

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace

  cleanup_on_fail = true
  atomic          = true
  timeout         = 600
  wait            = true

  values = [
    yamlencode({
      clusterName = local.cluster_name
      region      = var.aws_region
      vpcId       = data.terraform_remote_state.eks.outputs.vpc_id

      replicaCount = var.replica_count
      nodeSelector = var.node_selector

      enableServiceMutatorWebhook = var.enable_service_mutator_webhook

      # The worker ENIs have both the EKS primary SG and the shared node SG.
      # Both carry the cluster tag, so give the controller one additional tag
      # that uniquely identifies the SG where backend ingress rules belong.
      serviceTargetENISGTags = "Name=${local.cluster_name}-node"

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
