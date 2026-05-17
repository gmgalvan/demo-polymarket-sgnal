resource "helm_release" "neuron_device_plugin" {
  name             = "neuron-device-plugin"
  namespace        = var.plugin_namespace
  create_namespace = false
  repository       = "oci://public.ecr.aws/neuron"
  chart            = "neuron-helm-chart"

  set = [
    {
      name  = "npd.enabled"
      value = "false"
    }
  ]
}
