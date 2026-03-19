# ── AWS Neuron Monitor ──────────────────────────────────────────────────────
# Exports AWS Inferentia2/Trainium metrics from the Neuron SDK as Prometheus
# metrics. Equivalent of DCGM Exporter but for AWS custom silicon.
#
# neuron-monitor is a tool from the Neuron SDK that collects metrics from
# the Neuron runtime. With the `-p` flag it exposes a Prometheus endpoint.
# We run it as a DaemonSet ONLY on Neuron nodes (workload=neuron + toleration).
#
# Key metrics exposed:
#   neuroncore_utilization          — per-core compute utilization (%)
#   neuron_runtime_memory_used_bytes — device memory (HBM) used
#   neuron_runtime_vcpu_usage       — NeuronCore vCPU utilization
#   neuroncore_memory_usage_model_shared_scratchpad — model memory
#   neuron_instance_info            — hardware metadata (instance type, cores)
#   neuron_execution_latency        — inference execution latency
#   neuron_execution_errors_total   — runtime execution errors
#
# Reference: https://awsdocs-neuron.readthedocs-hosted.com/en/latest/tools/neuron-sys-tools/neuron-monitor-user-guide.html

resource "kubectl_manifest" "neuron_monitor_daemonset" {
  count            = var.install_neuron_monitor ? 1 : 0
  wait_for_rollout = false

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "DaemonSet"
    metadata = {
      name      = "neuron-monitor"
      namespace = var.monitoring_namespace
      labels = {
        "app.kubernetes.io/name"      = "neuron-monitor"
        "app.kubernetes.io/component" = "exporter"
        "app.kubernetes.io/part-of"   = "observability"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "neuron-monitor"
        }
      }
      template = {
        metadata = {
          labels = {
            "app.kubernetes.io/name"      = "neuron-monitor"
            "app.kubernetes.io/component" = "exporter"
            "app.kubernetes.io/part-of"   = "observability"
          }
          annotations = {
            "prometheus.io/scrape" = "true"
            "prometheus.io/port"   = "8000"
          }
        }
        spec = {
          # Only schedule on Inferentia/Trainium nodes
          nodeSelector = {
            workload = "neuron"
          }
          tolerations = [
            {
              key      = "aws.amazon.com/neuron"
              operator = "Exists"
              effect   = "NoSchedule"
            }
          ]

          containers = [
            {
              name = "neuron-monitor"
              # Official AWS Neuron monitor image used in the EKS guide.
              image = "public.ecr.aws/g4h4h0b5/neuron-monitor:1.0.0"
              command = [
                "/bin/sh",
                "-c",
                "neuron-monitor | /opt/aws/neuron/bin/neuron-monitor-prometheus.py --port 8000",
              ]
              ports = [
                {
                  name          = "metrics"
                  containerPort = 8000
                  protocol      = "TCP"
                }
              ]

              resources = {
                requests = {
                  cpu    = "50m"
                  memory = "64Mi"
                }
                limits = {
                  cpu    = "200m"
                  memory = "128Mi"
                }
              }

              securityContext = {
                privileged = true
              }
            }
          ]
        }
      }
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

# ── Neuron Monitor Service ──────────────────────────────────────────────────
# Headless service so the ServiceMonitor can discover neuron-monitor pods.

resource "kubectl_manifest" "neuron_monitor_service" {
  count = var.install_neuron_monitor ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "neuron-monitor"
      namespace = var.monitoring_namespace
      labels = {
        "app.kubernetes.io/name"      = "neuron-monitor"
        "app.kubernetes.io/component" = "exporter"
        "app.kubernetes.io/part-of"   = "observability"
      }
    }
    spec = {
      clusterIP = "None"
      selector = {
        "app.kubernetes.io/name" = "neuron-monitor"
      }
      ports = [
        {
          name       = "metrics"
          port       = 8000
          targetPort = "metrics"
          protocol   = "TCP"
        }
      ]
    }
  })
}

# ── Neuron ServiceMonitor ───────────────────────────────────────────────────
# Tells Prometheus to scrape neuron-monitor pods via the headless service.

resource "kubectl_manifest" "neuron_monitor_service_monitor" {
  count = var.install_kube_prometheus_stack && var.install_neuron_monitor ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "neuron-monitor"
      namespace = var.monitoring_namespace
      labels = {
        release                       = "kube-prometheus-stack"
        "app.kubernetes.io/name"      = "neuron-monitor"
        "app.kubernetes.io/component" = "exporter"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "neuron-monitor"
        }
      }
      namespaceSelector = {
        matchNames = [var.monitoring_namespace]
      }
      endpoints = [
        {
          port     = "metrics"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

# ── Neuron alerting rules ───────────────────────────────────────────────────
# PrometheusRule for Inferentia/Trainium hardware alerts.

resource "kubectl_manifest" "neuron_alerting_rules" {
  count = var.install_kube_prometheus_stack && var.install_neuron_monitor ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "neuron-alerting-rules"
      namespace = var.monitoring_namespace
      labels = {
        release = "kube-prometheus-stack"
        app     = "kube-prometheus-stack"
      }
    }
    spec = {
      groups = [
        {
          name = "neuron.rules"
          rules = [
            # ── NeuronCore utilization ───────────────────────────────────
            {
              alert = "NeuronCoreHighUtilization"
              expr  = "neuroncore_utilization > 95"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "NeuronCore utilization above 95% on {{ $labels.instance }}"
                description = "NeuronCore {{ $labels.neuroncore }} on node {{ $labels.instance }} has sustained >95% utilization for 5 minutes. Current: {{ $value | printf \"%.1f\" }}%. Consider scaling out with additional Inferentia nodes or optimizing batch sizes."
              }
            },
            {
              alert = "NeuronCoreLowUtilization"
              expr  = "neuroncore_utilization < 10"
              for   = "15m"
              labels = {
                severity = "info"
              }
              annotations = {
                summary     = "NeuronCore underutilized (<10%) on {{ $labels.instance }}"
                description = "NeuronCore {{ $labels.neuroncore }} on node {{ $labels.instance }} has been below 10% utilization for 15 minutes. Current: {{ $value | printf \"%.1f\" }}%. Inferentia nodes are charged per-hour — consider consolidating workloads."
              }
            },

            # ── Execution errors ─────────────────────────────────────────
            {
              alert = "NeuronExecutionErrors"
              expr  = "rate(neuron_execution_errors_total[5m]) > 0"
              for   = "2m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "Neuron execution errors detected on {{ $labels.instance }}"
                description = "NeuronCore on node {{ $labels.instance }} is reporting execution errors at {{ $value | printf \"%.2f\" }} errors/sec. This may indicate a model compilation mismatch, Neuron SDK bug, or hardware fault. Check neuron-top and dmesg on the node."
              }
            },

            # ── Device memory pressure ───────────────────────────────────
            {
              alert = "NeuronMemoryUsageHigh"
              expr  = "(neuron_runtime_memory_used_bytes / neuron_runtime_memory_total_bytes) * 100 > 90"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Neuron device memory usage above 90% on {{ $labels.instance }}"
                description = "Node {{ $labels.instance }} Neuron HBM usage is at {{ $value | printf \"%.1f\" }}%. Approaching the limit may cause OOM failures when loading models or increasing batch size."
              }
            },
            {
              alert = "NeuronMemoryUsageCritical"
              expr  = "(neuron_runtime_memory_used_bytes / neuron_runtime_memory_total_bytes) * 100 > 98"
              for   = "2m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "Neuron device memory nearly exhausted (>98%) on {{ $labels.instance }}"
                description = "Node {{ $labels.instance }} Neuron HBM usage is at {{ $value | printf \"%.1f\" }}%. Imminent OOM risk — reduce batch size or add Inferentia capacity."
              }
            },

            # ── Execution latency ────────────────────────────────────────
            {
              alert = "NeuronExecutionLatencyHigh"
              expr  = "neuron_execution_latency > 5000"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "Neuron execution latency above 5s on {{ $labels.instance }}"
                description = "Inference execution latency on node {{ $labels.instance }} has been above 5000ms for 5 minutes. Current: {{ $value | printf \"%.0f\" }}ms. This may indicate NeuronCore contention or an inefficient compiled model."
              }
            }
          ]
        }
      ]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}
