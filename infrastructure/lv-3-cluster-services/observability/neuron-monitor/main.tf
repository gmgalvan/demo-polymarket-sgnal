resource "kubectl_manifest" "neuron_monitor_daemonset" {
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
              name  = "neuron-monitor"
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
}

resource "kubectl_manifest" "neuron_monitor_service" {
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

resource "kubectl_manifest" "neuron_monitor_service_monitor" {
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
}

resource "kubectl_manifest" "neuron_alerting_rules" {
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
            {
              alert = "NeuronCoreHighUtilization"
              expr  = "neuroncore_utilization > 95"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary = "NeuronCore utilization above 95%"
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
                summary = "NeuronCore utilization below 10%"
              }
            },
            {
              alert = "NeuronExecutionErrors"
              expr  = "rate(neuron_execution_errors_total[5m]) > 0"
              for   = "2m"
              labels = {
                severity = "critical"
              }
              annotations = {
                summary = "Neuron execution errors detected"
              }
            },
            {
              alert = "NeuronMemoryUsageHigh"
              expr  = "(neuron_runtime_memory_used_bytes / neuron_runtime_memory_total_bytes) * 100 > 90"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary = "Neuron device memory usage above 90%"
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
                summary = "Neuron device memory usage above 98%"
              }
            },
            {
              alert = "NeuronExecutionLatencyHigh"
              expr  = "histogram_quantile(0.95, rate(neuron_execution_latency_bucket[5m])) > 5000"
              for   = "5m"
              labels = {
                severity = "warning"
              }
              annotations = {
                summary = "Neuron execution latency above 5000ms"
              }
            }
          ]
        }
      ]
    }
  })
}

resource "kubectl_manifest" "dashboard_neuron" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "grafana-dashboard-aws-neuron"
      namespace = var.monitoring_namespace
      labels = {
        grafana_dashboard = "1"
        app               = "kube-prometheus-stack-grafana"
      }
    }
    data = {
      "aws-neuron.json" = file("${path.module}/../../../modules/observability/dashboards/aws-neuron.json")
    }
  })
}
