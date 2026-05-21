data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket  = var.eks_state_bucket
    key     = var.eks_state_key
    region  = var.eks_state_region
    encrypt = true
  }
}

module "nvidia_device_plugin" {
  source = "../../modules/nvidia-device-plugin"

  plugin_namespace      = var.plugin_namespace
  time_slicing_enabled  = var.time_slicing_enabled
  time_slicing_replicas = var.time_slicing_replicas
}
