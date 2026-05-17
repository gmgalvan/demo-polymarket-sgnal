resource "helm_release" "kube_prometheus_stack" {
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
      prometheus = {
        prometheusSpec = {
          scrapeInterval     = "30s"
          evaluationInterval = "30s"
          scrapeTimeout      = "10s"
          retention          = var.prometheus_retention

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

          nodeSelector = {
            workload = "core"
          }
          tolerations = []
        }
      }

      grafana = {
        enabled       = true
        adminPassword = jsondecode(data.aws_secretsmanager_secret_version.grafana_admin_password.secret_string).password

        defaultDashboardsEnabled = true
        additionalDataSources = concat(
          var.enable_loki_datasource ? [
            {
              name      = "Loki"
              type      = "loki"
              url       = "http://loki-gateway.${var.logging_namespace}.svc.cluster.local:80"
              access    = "proxy"
              isDefault = false
            }
          ] : [],
          var.enable_tempo_datasource ? [
            {
              name      = "Tempo"
              type      = "tempo"
              url       = "http://otel-collector-opentelemetry-collector.${var.tracing_namespace}.svc.cluster.local:3200"
              access    = "proxy"
              isDefault = false
            }
          ] : []
        )

        nodeSelector = {
          workload = "core"
        }

        sidecar = {
          dashboards = {
            enabled         = true
            label           = "grafana_dashboard"
            labelValue      = "1"
            searchNamespace = "ALL"
          }
        }
      }

      alertmanager = {
        enabled = true
        alertmanagerSpec = {
          nodeSelector = {
            workload = "core"
          }
        }
      }

      kube-state-metrics = {
        nodeSelector = {
          workload = "core"
        }
      }

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

resource "helm_release" "prometheus_adapter" {
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

resource "kubectl_manifest" "dashboard_vllm" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "grafana-dashboard-vllm"
      namespace = var.monitoring_namespace
      labels = {
        grafana_dashboard = "1"
        app               = "kube-prometheus-stack-grafana"
      }
    }
    data = {
      "vllm-serving.json" = file("${path.module}/../../../shared/observability-assets/dashboards/vllm-serving.json")
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "dashboard_genai_overview" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "grafana-dashboard-genai-overview"
      namespace = var.monitoring_namespace
      labels = {
        grafana_dashboard = "1"
        app               = "kube-prometheus-stack-grafana"
      }
    }
    data = {
      "genai-overview.json" = file("${path.module}/../../../shared/observability-assets/dashboards/genai-overview.json")
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "vllm_service_monitor" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "vllm"
      namespace = var.monitoring_namespace
      labels = {
        release = "kube-prometheus-stack"
        app     = "vllm"
      }
    }
    spec = {
      namespaceSelector = {
        any = true
      }
      selector = {
        matchExpressions = [
          {
            key      = "app.kubernetes.io/name"
            operator = "In"
            values   = ["vllm"]
          }
        ]
      }
      endpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "vllm_pod_monitor_legacy" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "vllm-legacy"
      namespace = var.monitoring_namespace
      labels = {
        release = "kube-prometheus-stack"
        app     = "vllm"
      }
    }
    spec = {
      namespaceSelector = {
        any = true
      }
      selector = {
        matchExpressions = [
          {
            key      = "app.kubernetes.io/name"
            operator = "DoesNotExist"
          },
          {
            key      = "app"
            operator = "Exists"
          }
        ]
      }
      podMetricsEndpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "litellm_service_monitor" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "litellm"
      namespace = var.monitoring_namespace
      labels = {
        release = "kube-prometheus-stack"
        app     = "litellm"
      }
    }
    spec = {
      namespaceSelector = {
        any = true
      }
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "litellm"
        }
      }
      endpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "kserve_pod_monitor" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "kserve-inference"
      namespace = var.monitoring_namespace
      labels = {
        release = "kube-prometheus-stack"
        app     = "kserve"
      }
    }
    spec = {
      namespaceSelector = {
        any = true
      }
      selector = {
        matchExpressions = [
          {
            key      = "serving.kserve.io/inferenceservice"
            operator = "Exists"
          }
        ]
      }
      podMetricsEndpoints = [
        {
          port     = "http1"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "mcp_servers_pod_monitor" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "mcp-servers"
      namespace = var.monitoring_namespace
      labels = {
        release = "kube-prometheus-stack"
        app     = "mcp-server"
      }
    }
    spec = {
      namespaceSelector = {
        any = true
      }
      selector = {
        matchLabels = {
          "app.kubernetes.io/component" = "mcp-server"
        }
      }
      podMetricsEndpoints = [
        {
          port     = "http"
          path     = "/metrics"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubectl_manifest" "llm_alerting_rules" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "llm-alerting-rules"
      namespace = var.monitoring_namespace
      labels = {
        release = "kube-prometheus-stack"
        app     = "kube-prometheus-stack"
      }
    }
    spec = {
      groups = [
        {
          name = "llm.rules"
          rules = [
            {
              alert = "VLLMHighTimePerOutputToken"
              expr  = "histogram_quantile(0.95, rate(vllm:time_per_output_token_seconds_bucket[5m])) >= 0.3"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary = "vLLM P95 time-per-output-token above 300ms"
              }
            },
            {
              alert = "VLLMHighE2ELatency"
              expr  = "histogram_quantile(0.95, rate(vllm:e2e_request_latency_seconds_bucket[5m])) >= 30"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary = "vLLM end-to-end request latency above 30s"
              }
            },
            {
              alert = "VLLMHighTimeToFirstToken"
              expr  = "histogram_quantile(0.95, rate(vllm:time_to_first_token_seconds_bucket[5m])) >= 10"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary = "vLLM P95 time-to-first-token above 10s"
              }
            },
            {
              alert = "VLLMRequestQueueGrowing"
              expr  = "sum(vllm:num_requests_waiting) > 10"
              for   = "3m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary = "vLLM request queue above 10"
              }
            },
            {
              alert = "VLLMRequestQueueCritical"
              expr  = "sum(vllm:num_requests_waiting) > 50"
              for   = "1m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary = "vLLM request queue above 50"
              }
            }
          ]
        }
      ]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}
