locals {
  tags = merge(
    var.common_tags,
    {
      "karpenter.sh/discovery" = var.cluster_name
    }
  )
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access           = var.eks_endpoint_public_access
  enable_cluster_creator_admin_permissions = true

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  eks_managed_node_group_defaults = {
    ami_type                              = "AL2_x86_64"
    attach_cluster_primary_security_group = true
    iam_role_additional_policies = {
      AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
  }

  eks_managed_node_groups = {
    core = {
      instance_types = [var.core_node_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = var.core_node_min_size
      desired_size = var.core_node_desired_size
      max_size     = var.core_node_max_size

      labels = {
        workload = "core"
      }
    }

    l40s = {
      ami_type       = "AL2_x86_64_GPU"
      instance_types = [var.l40s_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = var.l40s_node_min_size
      desired_size = var.l40s_node_desired_size
      max_size     = var.l40s_node_max_size
      disk_size    = var.l40s_node_disk_size

      labels = {
        accelerator = "nvidia-l40s"
        workload    = "gpu"
      }

      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }

    inferentia = {
      ami_type       = "AL2_x86_64"
      instance_types = [var.inferentia_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = var.inferentia_node_min_size
      desired_size = var.inferentia_node_desired_size
      max_size     = var.inferentia_node_max_size
      disk_size    = var.inferentia_node_disk_size

      labels = {
        accelerator = "aws-inferentia2"
        workload    = "neuron"
      }

      taints = {
        neuron = {
          key    = "aws.amazon.com/neuron"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  tags = local.tags
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name          = module.eks.cluster_name
  enable_v1_permissions = true

  create_instance_profile = true
  enable_irsa             = true
  irsa_oidc_provider_arn  = module.eks.oidc_provider_arn
  irsa_namespace_service_accounts = [
    "${var.karpenter_namespace}:karpenter"
  ]

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }

  tags = var.common_tags

  depends_on = [module.eks]
}
