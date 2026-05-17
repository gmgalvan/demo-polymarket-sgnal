resource "helm_release" "dcgm_exporter" {
  name             = "dcgm-exporter"
  namespace        = var.monitoring_namespace
  create_namespace = false
  repository       = "https://nvidia.github.io/dcgm-exporter/helm-charts"
  chart            = "dcgm-exporter"
  version          = var.dcgm_exporter_chart_version

  values = [
    yamlencode({
      nodeSelector = {
        workload = "gpu"
      }
      tolerations = [
        {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]

      serviceMonitor = {
        enabled   = true
        namespace = var.monitoring_namespace
        additionalLabels = {
          release = "kube-prometheus-stack"
        }
      }
    })
  ]
}

resource "kubectl_manifest" "gpu_alerting_rules" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "gpu-alerting-rules"
      namespace = var.monitoring_namespace
      labels = {
        release = "kube-prometheus-stack"
        app     = "kube-prometheus-stack"
      }
    }
    spec = {
      groups = [
        {
          name = "gpu.rules"
          rules = [
            {
              alert = "GPUMemoryUsageHigh"
              expr  = "(DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE)) * 100 > 90"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary = "GPU memory usage above 90%"
              }
            },
            {
              alert = "GPUHighUtilization"
              expr  = "DCGM_FI_DEV_GPU_UTIL > 95"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary = "GPU utilization above 95%"
              }
            },
            {
              alert = "GPULowUtilization"
              expr  = "DCGM_FI_DEV_GPU_UTIL < 20"
              for   = "15m"
              labels = {
                severity = "info"
              }
              annotations = {
                summary = "GPU utilization below 20%"
              }
            },
            {
              alert = "GPUTemperatureTooHigh"
              expr  = "DCGM_FI_DEV_GPU_TEMP > 85"
              for   = "3m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary = "GPU temperature above 85C"
              }
            },
            {
              alert = "GPUXidErrorDetected"
              expr  = "DCGM_FI_DEV_XID_ERRORS != 0"
              for   = "1m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary = "GPU Xid error detected"
              }
            }
          ]
        }
      ]
    }
  })
}

resource "kubectl_manifest" "dashboard_gpu" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "grafana-dashboard-nvidia-gpu"
      namespace = var.monitoring_namespace
      labels = {
        grafana_dashboard = "1"
        app               = "kube-prometheus-stack-grafana"
      }
    }
    data = {
      "nvidia-gpu.json" = file("${path.module}/../../../shared/observability-assets/dashboards/nvidia-gpu.json")
    }
  })
}
