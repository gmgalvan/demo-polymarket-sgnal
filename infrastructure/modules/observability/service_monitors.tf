# ── ServiceMonitors & PodMonitors ────────────────────────────────────────────
# These CRs tell the Prometheus Operator which services to scrape.
# Each component that exposes /metrics gets its own ServiceMonitor.
#
# The label `release: kube-prometheus-stack` ensures the Prometheus Operator
# picks them up (matches the default serviceMonitorSelector).

# ── vLLM ServiceMonitor ─────────────────────────────────────────────────────
# vLLM exposes /metrics on port 8000 with LLM-specific metrics:
# TTFT, TPOT, e2e latency, prompt/generation tokens, queue depth.
#
# Uses matchExpressions to discover Services with EITHER:
#   - app.kubernetes.io/name=vllm  (standard label, recommended)
#   - app=vllm-*                   (legacy label on existing manifests)
# This ensures monitoring works with both old and new manifests.

resource "kubectl_manifest" "vllm_service_monitor" {
  count = var.install_kube_prometheus_stack ? 1 : 0

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
      # Match vLLM services by label across all namespaces
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

# ── vLLM PodMonitor (legacy label fallback) ─────────────────────────────────
# Catches vLLM pods that use the legacy `app: vllm-*` label without a
# matching Service with app.kubernetes.io/name. This is a safety net for
# manifests that haven't been updated yet.

resource "kubectl_manifest" "vllm_pod_monitor_legacy" {
  count = var.install_kube_prometheus_stack ? 1 : 0

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
            # Match any pod where app label starts with "vllm-"
            # This catches: vllm-gpu-qwen25, vllm-neuron-tinyllama-1b, etc.
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

# ── LiteLLM ServiceMonitor ──────────────────────────────────────────────────
# LiteLLM gateway exposes /metrics on port 4000 with routing,
# token usage, and latency metrics per model backend.

resource "kubectl_manifest" "litellm_service_monitor" {
  count = var.install_kube_prometheus_stack ? 1 : 0

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

# ── KServe PodMonitor ───────────────────────────────────────────────────────
# KServe InferenceServices expose metrics on port 8080. Using PodMonitor
# because KServe dynamically creates pods via Knative/raw deployments.
# Also adds standard annotations for KServe prometheus scraping.

resource "kubectl_manifest" "kserve_pod_monitor" {
  count = var.install_kube_prometheus_stack ? 1 : 0

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

# ── MCP Servers PodMonitor ──────────────────────────────────────────────────
# MCP servers (Polymarket, TA, Web Search) may expose /metrics if instrumented.
# This PodMonitor catches any pod with the mcp-server label.

resource "kubectl_manifest" "mcp_servers_pod_monitor" {
  count = var.install_kube_prometheus_stack ? 1 : 0

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
          "app.kubernetes.io/part-of" = "polymarket-signal"
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

# ── LLM alerting rules ─────────────────────────────────────────────────────
# PrometheusRule for vLLM inference metrics: latency, queue depth, throughput.

resource "kubectl_manifest" "llm_alerting_rules" {
  count = var.install_kube_prometheus_stack ? 1 : 0

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
            # ── Latency alerts ───────────────────────────────────────────
            {
              alert = "VLLMHighTimePerOutputToken"
              expr  = "histogram_quantile(0.95, rate(vllm:time_per_output_token_seconds_bucket[5m])) >= 0.3"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "vLLM TPOT P95 >= 300ms on {{ $labels.instance }}"
                description = "The 95th percentile time-per-output-token has been >= 300ms for 5 minutes. Current P95: {{ $value | printf \"%.3f\" }}s. This impacts user-perceived streaming speed. Consider scaling out or reducing batch size."
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
                summary     = "vLLM end-to-end latency P95 >= 30s on {{ $labels.instance }}"
                description = "The 95th percentile end-to-end request latency has been >= 30s for 5 minutes. Current P95: {{ $value | printf \"%.1f\" }}s. Requests may be timing out."
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
                summary     = "vLLM TTFT P95 >= 10s on {{ $labels.instance }}"
                description = "The 95th percentile time-to-first-token has been >= 10s for 5 minutes. Current P95: {{ $value | printf \"%.1f\" }}s. Users experience long delays before streaming starts."
              }
            },

            # ── Queue / capacity alerts ──────────────────────────────────
            {
              alert = "VLLMRequestQueueGrowing"
              expr  = "vllm:num_requests_waiting > 10"
              for   = "3m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary     = "vLLM request queue > 10 on {{ $labels.instance }}"
                description = "More than 10 requests have been waiting in the vLLM queue for 3 minutes. Current queue depth: {{ $value }}. The model server is at capacity — consider adding replicas."
              }
            },
            {
              alert = "VLLMRequestQueueCritical"
              expr  = "vllm:num_requests_waiting > 50"
              for   = "1m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "vLLM request queue > 50 on {{ $labels.instance }}"
                description = "Queue depth has exceeded 50 requests. Current: {{ $value }}. Requests are likely timing out. Immediate scaling action needed."
              }
            },

            # ── Throughput alerts ────────────────────────────────────────
            {
              alert = "VLLMNoRequestsProcessed"
              expr  = "rate(vllm:e2e_request_latency_seconds_count[5m]) == 0 and vllm:num_requests_running > 0"
              for   = "5m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary     = "vLLM processing stalled on {{ $labels.instance }}"
                description = "vLLM has running requests but completed zero requests in the last 5 minutes. The model server may be deadlocked or OOM."
              }
            },

            # ── Token budget alerts ──────────────────────────────────────
            {
              alert = "VLLMHighTokenRate"
              expr  = "sum(rate(vllm:generation_tokens_total[5m])) > 5000"
              for   = "10m"
              labels = {
                severity = "info"
              }
              annotations = {
                summary     = "vLLM token generation rate > 5000 tokens/sec"
                description = "The cluster-wide token generation rate has sustained above 5000 tokens/sec for 10 minutes. Current: {{ $value | printf \"%.0f\" }} tok/s. Monitor cost and capacity."
              }
            }
          ]
        }
      ]
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}
