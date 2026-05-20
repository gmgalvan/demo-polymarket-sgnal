resource "helm_release" "nvidia_device_plugin" {
  name             = "nvidia-device-plugin"
  namespace        = var.plugin_namespace
  create_namespace = false
  repository       = "https://nvidia.github.io/k8s-device-plugin"
  chart            = "nvidia-device-plugin"

  values = [
    yamlencode({
      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key      = "workload"
                    operator = "In"
                    values   = ["gpu", "gpu-nim"]
                  }
                ]
              }
            ]
          }
        }
      }
      gfd = {
        enabled = false
      }
      tolerations = [
        {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]
}
