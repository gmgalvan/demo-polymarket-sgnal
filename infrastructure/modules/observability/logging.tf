# ── Loki (Log Aggregation Backend) ──────────────────────────────────────────
# Loki stores and indexes log streams collected by Fluent Bit.
# Deployed in single-binary mode for simplicity (suitable for demo / dev).
# Grafana queries Loki via the data source configured in kube-prometheus-stack.

resource "helm_release" "loki" {
  count = var.install_loki_stack ? 1 : 0

  name             = "loki"
  namespace        = var.logging_namespace
  create_namespace = true
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = var.loki_chart_version

  timeout         = 600
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      # Single-binary deployment (no microservices) — good for demo
      deploymentMode = "SingleBinary"

      loki = {
        auth_enabled = false

        commonConfig = {
          replication_factor = 1
        }

        storage = {
          type = "filesystem"
        }

        schemaConfig = {
          configs = [
            {
              from         = "2024-01-01"
              store        = "tsdb"
              object_store = "filesystem"
              schema       = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            }
          ]
        }
      }

      singleBinary = {
        replicas = 1
        nodeSelector = {
          workload = "core"
        }
        persistence = {
          enabled      = true
          size         = "10Gi"
          storageClass = var.loki_storage_class != "" ? var.loki_storage_class : null
        }
      }

      # Disable components not needed in single-binary mode
      read         = { replicas = 0 }
      write        = { replicas = 0 }
      backend      = { replicas = 0 }
      gateway      = { enabled = true }
      chunksCache  = { enabled = false }
      resultsCache = { enabled = false }
    })
  ]
}

# ── Fluent Bit (Log Collector DaemonSet) ────────────────────────────────────
# Runs on every node (including GPU/Inferentia nodes via tolerations).
# Collects container stdout/stderr from /var/log/containers/ and
# forwards to Loki via the Loki output plugin.

resource "helm_release" "fluent_bit" {
  count = var.install_loki_stack ? 1 : 0

  name             = "fluent-bit"
  namespace        = var.logging_namespace
  create_namespace = false
  repository       = "https://fluent.github.io/helm-charts"
  chart            = "fluent-bit"
  version          = var.fluent_bit_chart_version

  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      # Run on ALL nodes (core, GPU, Inferentia) to collect all logs
      tolerations = [
        {
          operator = "Exists"
        }
      ]

      config = {
        service = <<-EOT
          [SERVICE]
              Flush         5
              Log_Level     info
              Daemon        off
              Parsers_File  /fluent-bit/etc/parsers.conf
              HTTP_Server   On
              HTTP_Listen   0.0.0.0
              HTTP_Port     2020
              Health_Check  On
        EOT

        inputs = <<-EOT
          [INPUT]
              Name              tail
              Tag               kube.*
              Path              /var/log/containers/*.log
              multiline.parser  docker, cri
              Mem_Buf_Limit     5MB
              Skip_Long_Lines   On
              Refresh_Interval  10
        EOT

        filters = <<-EOT
          [FILTER]
              Name                kubernetes
              Match               kube.*
              Kube_URL            https://kubernetes.default.svc:443
              Kube_CA_File        /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              Kube_Token_File     /var/run/secrets/kubernetes.io/serviceaccount/token
              Kube_Tag_Prefix     kube.var.log.containers.
              Merge_Log           On
              Keep_Log            Off
              K8S-Logging.Parser  On
              K8S-Logging.Exclude Off
              Labels              On
              Annotations         Off
        EOT

        outputs = <<-EOT
          [OUTPUT]
              Name        loki
              Match       kube.*
              Host        loki-gateway.${var.logging_namespace}.svc.cluster.local
              Port        80
              Labels      job=fluent-bit, namespace=$kubernetes['namespace_name'], pod=$kubernetes['pod_name'], container=$kubernetes['container_name']
              Auto_Kubernetes_Labels Off
        EOT
      }

      # Expose /api/v1/metrics for Prometheus scraping
      serviceMonitor = {
        enabled = var.install_kube_prometheus_stack
        additionalLabels = {
          release = "kube-prometheus-stack"
        }
      }
    })
  ]

  depends_on = [helm_release.loki]
}
