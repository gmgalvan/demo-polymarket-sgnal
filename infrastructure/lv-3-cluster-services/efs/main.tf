################################################################################
# Remote State — pull VPC and EKS outputs
################################################################################

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "352-demo-dev-s3b-tfstate-backend"
    key    = "dev/lv-2-core-compute/eks/terraform.tfstate"
    region = var.aws_region
  }
}

################################################################################
# Locals
################################################################################

locals {
  name = "${data.terraform_remote_state.eks.outputs.cluster_name}-model-store"

  # Use first 3 private subnets (one per AZ) for mount targets.
  # lv-0 creates 6 private subnets (2 per AZ); we only need one per AZ.
  mount_target_subnets = slice(
    data.terraform_remote_state.eks.outputs.private_subnet_ids, 0, 3
  )

  tags = {
    Project   = "demo-polymarket-signal"
    Layer     = "lv-3-cluster-services"
    Component = "efs-model-store"
    ManagedBy = "terraform"
  }
}

################################################################################
# EFS Module
################################################################################

module "efs" {
  source = "../../modules/efs"

  name                   = local.name
  vpc_id                 = data.terraform_remote_state.eks.outputs.vpc_id
  subnet_ids             = local.mount_target_subnets
  node_security_group_id = data.terraform_remote_state.eks.outputs.node_security_group_id
  additional_allowed_security_group_ids = [
    data.terraform_remote_state.eks.outputs.cluster_primary_security_group_id
  ]
  oidc_provider_arn      = data.terraform_remote_state.eks.outputs.cluster_oidc_provider_arn

  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  install_efs_csi_driver = var.install_efs_csi_driver
  create_storage_class   = var.create_storage_class
  storage_class_name     = "efs-sc"

  tags = local.tags
}

resource "kubectl_manifest" "storage_class_nim" {
  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = "efs-sc-nim"
    }
    provisioner = "efs.csi.aws.com"
    parameters = {
      provisioningMode = "efs-ap"
      fileSystemId     = module.efs.file_system_id
      directoryPerms   = "770"
      uid              = "1000"
      gid              = "2000"
    }
    reclaimPolicy     = "Retain"
    volumeBindingMode = "Immediate"
  })

  depends_on = [module.efs]
}
