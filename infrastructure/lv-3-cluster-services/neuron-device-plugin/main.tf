data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket  = var.eks_state_bucket
    key     = var.eks_state_key
    region  = var.eks_state_region
    encrypt = true
  }
}

module "neuron_device_plugin" {
  source = "../../modules/neuron-device-plugin"

  plugin_namespace = var.plugin_namespace
}
