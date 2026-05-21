locals {
  base_values = {
    affinity = {
      nodeAffinity = {
        requiredDuringSchedulingIgnoredDuringExecution = {
          nodeSelectorTerms = [
            {
              matchExpressions = [
                {
                  key      = "workload"
                  operator = "In"
                  values   = ["gpu", "gpu-nim", "gpu-fixed", "gpu-fixed-hi-mem"]
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
  }

  time_slicing_values = var.time_slicing_enabled ? {
    config = {
      map = {
        default = <<-EOT
          version: v1
          flags:
            migStrategy: none
          sharing:
            timeSlicing:
              renameByDefault: false
              failRequestsGreaterThanOne: true
              resources:
                - name: nvidia.com/gpu
                  replicas: ${var.time_slicing_replicas}
        EOT
      }
    }
  } : {}
}

resource "helm_release" "nvidia_device_plugin" {
  name             = "nvidia-device-plugin"
  namespace        = var.plugin_namespace
  create_namespace = false
  repository       = "https://nvidia.github.io/k8s-device-plugin"
  chart            = "nvidia-device-plugin"

  values = [
    yamlencode(merge(local.base_values, local.time_slicing_values))
  ]
}
