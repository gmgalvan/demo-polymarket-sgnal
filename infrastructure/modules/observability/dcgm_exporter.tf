# ── NVIDIA DCGM Exporter ────────────────────────────────────────────────────
# Exports GPU metrics (utilization, memory, temperature, ECC errors, power)
# from NVIDIA Data Center GPU Manager as Prometheus metrics.
# Runs as a DaemonSet ONLY on GPU nodes via nodeSelector + tolerations.

resource "helm_release" "dcgm_exporter" {
  count = var.install_dcgm_exporter ? 1 : 0

  name             = "dcgm-exporter"
  namespace        = var.monitoring_namespace
  create_namespace = false
  repository       = "https://nvidia.github.io/dcgm-exporter/helm-charts"
  chart            = "dcgm-exporter"
  version          = var.dcgm_exporter_chart_version

  values = [
    yamlencode({
      # Only schedule on GPU nodes
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

      # Enable ServiceMonitor so kube-prometheus-stack scrapes GPU metrics
      serviceMonitor = {
        enabled   = true
        namespace = var.monitoring_namespace
        additionalLabels = {
          release = "kube-prometheus-stack"
        }
      }
    })
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}

# ── GPU alerting rules ──────────────────────────────────────────────────────
# PrometheusRule CR picked up automatically by the kube-prometheus-stack
# Prometheus operator. Covers memory saturation, utilization extremes,
# thermal throttling, and Xid hardware errors.

resource "kubectl_manifest" "gpu_alerting_rules" {
  count = var.install_kube_prometheus_stack && var.install_dcgm_exporter ? 1 : 0

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
                summary     = "GPU memory usage above 90% on {{ $labels.gpu }} ({{ $labels.instance }})"
                description = "GPU {{ $labels.gpu }} on node {{ $labels.instance }} has been using more than 90% of its framebuffer memory for 5 minutes. Current: {{ $value | printf \"%.1f\" }}%. This may cause OOM errors for new model loading or inference batches."
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
                summary     = "GPU utilization above 95% on {{ $labels.gpu }} ({{ $labels.instance }})"
                description = "GPU {{ $labels.gpu }} on node {{ $labels.instance }} has sustained >95% utilization for 5 minutes. Current: {{ $value | printf \"%.1f\" }}%. Consider scaling out with additional GPU nodes or optimizing batch sizes."
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
                summary     = "GPU underutilized (<20%) on {{ $labels.gpu }} ({{ $labels.instance }})"
                description = "GPU {{ $labels.gpu }} on node {{ $labels.instance }} has been below 20% utilization for 15 minutes. Current: {{ $value | printf \"%.1f\" }}%. Consider scaling down or consolidating workloads to reduce cost."
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
                summary     = "GPU temperature above 85°C on {{ $labels.gpu }} ({{ $labels.instance }})"
                description = "GPU {{ $labels.gpu }} on node {{ $labels.instance }} is at {{ $value }}°C. Sustained temperatures above 85°C may trigger thermal throttling or hardware damage. Check cooling and workload."
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
                summary     = "GPU Xid error detected on {{ $labels.gpu }} ({{ $labels.instance }})"
                description = "GPU {{ $labels.gpu }} on node {{ $labels.instance }} reported Xid error code {{ $value }}. Xid errors indicate hardware or driver faults. Check `dmesg` and consider draining the node."
              }
            }
          ]
        }
      ]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}
