resource "helm_release" "otel_collector" {
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
          resource = {
            attributes = [
              {
                key    = "cluster.name"
                value  = data.terraform_remote_state.eks.outputs.cluster_name
                action = "upsert"
              }
            ]
          }
        }

        exporters = {
          prometheus = {
            endpoint          = "0.0.0.0:8889"
            namespace         = "otel"
            send_timestamps   = true
            metric_expiration = "5m"
          }
          otlp = var.export_to_langfuse ? {
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
          debug = {
            verbosity = "basic"
          }
        }

        connectors = {
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

      serviceMonitor = {
        enabled = var.enable_service_monitor
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
