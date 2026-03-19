# ── LangFuse (LLM Observability) ────────────────────────────────────────────
# LangFuse provides LLM-specific observability:
#   - Prompt/response tracing with full conversation history
#   - Token usage tracking per model, per request
#   - Latency breakdowns (TTFT, generation, total)
#   - Cost estimation per model call
#   - Evaluation scores and feedback collection
#
# The Strands agent SDK has built-in OpenTelemetry support. LangFuse
# ingests OTLP traces from the OTel Collector, giving end-to-end
# visibility from agent decision → LiteLLM gateway → vLLM inference.
#
# LangFuse requires PostgreSQL for persistence. This deployment uses the
# bundled PostgreSQL sub-chart for simplicity. In production, use
# Amazon RDS or Aurora.

resource "helm_release" "langfuse" {
  count = var.install_langfuse ? 1 : 0

  name             = "langfuse"
  namespace        = var.langfuse_namespace
  create_namespace = true
  repository       = "https://langfuse.github.io/langfuse-k8s"
  chart            = "langfuse"
  version          = var.langfuse_chart_version

  timeout = 600

  values = [
    yamlencode({
      langfuse = {
        nextauth = {
          secret = {
            value = var.langfuse_nextauth_secret
          }
          url = "http://langfuse.${var.langfuse_namespace}.svc.cluster.local:3000"
        }

        salt = {
          value = var.langfuse_salt
        }

        telemetry = {
          enabled = false
        }
      }

      # Bundled PostgreSQL (use RDS in production)
      postgresql = {
        enabled = true
        auth = {
          password = var.langfuse_postgres_password
          database = "langfuse"
        }
        primary = {
          nodeSelector = {
            workload = "core"
          }
          persistence = {
            enabled      = true
            size         = "10Gi"
            storageClass = var.langfuse_postgres_storage_class != "" ? var.langfuse_postgres_storage_class : null
          }
        }
      }

      nodeSelector = {
        workload = "core"
      }

      service = {
        type = "ClusterIP"
        port = 3000
      }
    })
  ]
}
