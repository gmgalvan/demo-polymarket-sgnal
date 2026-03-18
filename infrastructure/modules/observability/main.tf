# ── kube-prometheus-stack ────────────────────────────────────────────────────
# Deploys Prometheus, Grafana, Alertmanager, kube-state-metrics, and
# node-exporter in a single Helm release. This is the foundation of the
# monitoring stack — all other components export metrics here.

resource "helm_release" "kube_prometheus_stack" {
  count = var.install_kube_prometheus_stack ? 1 : 0

  name             = "kube-prometheus-stack"
  namespace        = var.monitoring_namespace
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kube_prometheus_stack_chart_version

  timeout = 900
  wait    = true

  values = [
    yamlencode({
      # ── Prometheus server ──────────────────────────────────────────────
      prometheus = {
        prometheusSpec = {
          scrapeInterval     = "30s"
          evaluationInterval = "30s"
          scrapeTimeout      = "10s"
          retention          = var.prometheus_retention

          # Discover all ServiceMonitors/PodMonitors across namespaces
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          ruleSelectorNilUsesHelmValues           = false

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = var.prometheus_storage_class != "" ? var.prometheus_storage_class : null
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }

          # Run Prometheus on ARM (Graviton) core nodes — cheap compute
          nodeSelector = {
            workload = "core"
          }
          tolerations = []
        }
      }

      # ── Grafana ────────────────────────────────────────────────────────
      grafana = {
        enabled = true
        adminPassword = var.grafana_admin_password

        # Default dashboards (K8s compute resources, node exporter, etc.)
        defaultDashboardsEnabled = true

        # Additional data sources configured below (Loki, Tempo)
        additionalDataSources = concat(
          var.install_loki_stack ? [
            {
              name      = "Loki"
              type      = "loki"
              url       = "http://loki-gateway.${var.logging_namespace}.svc.cluster.local:80"
              access    = "proxy"
              isDefault = false
            }
          ] : [],
          var.install_otel_collector ? [
            {
              name      = "Tempo"
              type      = "tempo"
              url       = "http://otel-collector.${var.tracing_namespace}.svc.cluster.local:3200"
              access    = "proxy"
              isDefault = false
            }
          ] : []
        )

        nodeSelector = {
          workload = "core"
        }

        # Load custom dashboards from ConfigMaps with label grafana_dashboard=1
        sidecar = {
          dashboards = {
            enabled         = true
            label           = "grafana_dashboard"
            labelValue      = "1"
            searchNamespace = "ALL"
          }
        }
      }

      # ── Alertmanager ───────────────────────────────────────────────────
      alertmanager = {
        enabled = true
        alertmanagerSpec = {
          nodeSelector = {
            workload = "core"
          }
        }
      }

      # ── kube-state-metrics on ARM ─────────────────────────────────────
      kube-state-metrics = {
        nodeSelector = {
          workload = "core"
        }
      }

      # ── node-exporter on ALL nodes (DaemonSet) ────────────────────────
      prometheus-node-exporter = {
        tolerations = [
          {
            operator = "Exists"
          }
        ]
      }
    })
  ]
}

# ── prometheus-adapter ──────────────────────────────────────────────────────
# Exposes Prometheus metrics as Kubernetes custom/external metrics so that
# HPA can scale pods based on vLLM queue depth, GPU utilization, etc.

resource "helm_release" "prometheus_adapter" {
  count = var.install_kube_prometheus_stack && var.install_prometheus_adapter ? 1 : 0

  name             = "prometheus-adapter"
  namespace        = var.monitoring_namespace
  create_namespace = false
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus-adapter"
  version          = var.prometheus_adapter_chart_version

  values = [
    yamlencode({
      prometheus = {
        url  = "http://kube-prometheus-stack-prometheus.${var.monitoring_namespace}.svc.cluster.local"
        port = 9090
      }

      rules = {
        custom = [
          {
            # Expose vLLM waiting requests as a custom metric for HPA
            seriesQuery = "vllm:num_requests_waiting"
            resources = {
              overrides = {
                namespace = { resource = "namespace" }
                pod       = { resource = "pod" }
              }
            }
            name = {
              matches = "^(.*)$"
              as      = "vllm_requests_waiting"
            }
            metricsQuery = "sum(<<.Series>>{<<.LabelMatchers>>}) by (<<.GroupBy>>)"
          },
          {
            # Expose vLLM running requests
            seriesQuery = "vllm:num_requests_running"
            resources = {
              overrides = {
                namespace = { resource = "namespace" }
                pod       = { resource = "pod" }
              }
            }
            name = {
              matches = "^(.*)$"
              as      = "vllm_requests_running"
            }
            metricsQuery = "sum(<<.Series>>{<<.LabelMatchers>>}) by (<<.GroupBy>>)"
          }
        ]
      }

      nodeSelector = {
        workload = "core"
      }
    })
  ]

  depends_on = [helm_release.kube_prometheus_stack]
}
