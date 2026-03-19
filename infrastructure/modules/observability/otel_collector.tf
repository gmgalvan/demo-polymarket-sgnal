# ── OpenTelemetry Collector ──────────────────────────────────────────────────
# Central hub for distributed traces. Receives OTLP (gRPC + HTTP) from:
#   - vLLM (--otlp-traces-endpoint flag)
#   - Strands agents (OpenTelemetry SDK)
#   - MCP servers (if instrumented)
#   - LiteLLM gateway
#
# Exports traces to LangFuse (OTLP) and optionally to Jaeger/Tempo.
# Also exports span metrics to Prometheus for latency dashboards.

resource "helm_release" "otel_collector" {
  count = var.install_otel_collector ? 1 : 0

  name             = "otel-collector"
  namespace        = var.tracing_namespace
  create_namespace = true
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  version          = var.otel_collector_chart_version

  values = [
    yamlencode({
      mode = "deployment"

      image = {
        repository = "otel/opentelemetry-collector-contrib"
      }

      replicaCount = 1

      nodeSelector = {
        workload = "core"
      }

      config = {
        receivers = {
          otlp = {
            protocols = {
              grpc = {
                endpoint = "0.0.0.0:${var.otel_otlp_grpc_port}"
              }
              http = {
                endpoint = "0.0.0.0:${var.otel_otlp_http_port}"
              }
            }
          }
        }

        processors = {
          batch = {
            timeout         = "5s"
            send_batch_size = 512
          }

          memory_limiter = {
            check_interval         = "5s"
            limit_percentage       = 80
            spike_limit_percentage = 25
          }

          # Add resource attributes for service identification
          resource = {
            attributes = [
              {
                key    = "cluster.name"
                value  = var.cluster_name
                action = "upsert"
              }
            ]
          }
        }

        exporters = {
          # Export to Prometheus for span metrics (request count, duration)
          prometheus = {
            endpoint          = "0.0.0.0:8889"
            namespace         = "otel"
            send_timestamps   = true
            metric_expiration = "5m"
          }

          # OTLP exporter to LangFuse (if installed)
          otlp = var.install_langfuse ? {
            endpoint = "http://langfuse.${var.langfuse_namespace}.svc.cluster.local:3000"
            tls = {
              insecure = true
            }
            } : {
            endpoint = "localhost:4317"
            tls = {
              insecure = true
            }
          }

          # Debug exporter for development (logs traces to stdout)
          debug = {
            verbosity = "basic"
          }
        }

        connectors = {
          # Generate metrics from spans (RED metrics: Rate, Errors, Duration)
          spanmetrics = {
            histogram = {
              explicit = {
                buckets = ["100us", "1ms", "2ms", "6ms", "10ms", "100ms", "250ms", "500ms", "1s", "5s", "10s", "30s"]
              }
            }
            dimensions = [
              { name = "http.method" },
              { name = "http.status_code" }
            ]
          }
        }

        service = {
          pipelines = {
            traces = {
              receivers  = ["otlp"]
              processors = ["memory_limiter", "resource", "batch"]
              exporters  = ["otlp", "spanmetrics", "debug"]
            }
            "metrics/spanmetrics" = {
              receivers = ["spanmetrics"]
              exporters = ["prometheus"]
            }
          }

          telemetry = {
            logs = {
              level = "info"
            }
          }
        }
      }

      # Expose ports for receiving traces and serving Prometheus metrics
      ports = {
        otlp = {
          enabled       = true
          containerPort = var.otel_otlp_grpc_port
          servicePort   = var.otel_otlp_grpc_port
          protocol      = "TCP"
        }
        otlp-http = {
          enabled       = true
          containerPort = var.otel_otlp_http_port
          servicePort   = var.otel_otlp_http_port
          protocol      = "TCP"
        }
        prometheus = {
          enabled       = true
          containerPort = 8889
          servicePort   = 8889
          protocol      = "TCP"
        }
      }

      # ServiceMonitor for the collector's own metrics + span metrics
      serviceMonitor = {
        enabled = var.install_kube_prometheus_stack
        additionalLabels = {
          release = "kube-prometheus-stack"
        }
        extraEndpoints = [
          {
            port     = "prometheus"
            interval = "30s"
          }
        ]
      }
    })
  ]
}
