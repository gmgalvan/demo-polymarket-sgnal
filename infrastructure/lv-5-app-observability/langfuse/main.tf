resource "helm_release" "langfuse" {
  name             = "langfuse"
  namespace        = var.langfuse_namespace
  create_namespace = true
  repository       = "https://langfuse.github.io/langfuse-k8s"
  chart            = "langfuse"
  version          = var.langfuse_chart_version

  timeout         = 600
  atomic          = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      global = {
        defaultStorageClass = var.langfuse_postgres_storage_class != "" ? var.langfuse_postgres_storage_class : null
      }

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

      clickhouse = {
        auth = {
          password = var.langfuse_postgres_password
        }
        persistence = {
          storageClass = var.langfuse_postgres_storage_class != "" ? var.langfuse_postgres_storage_class : null
        }
      }

      redis = {
        auth = {
          password = var.langfuse_postgres_password
        }
        master = {
          persistence = {
            storageClass = var.langfuse_postgres_storage_class != "" ? var.langfuse_postgres_storage_class : null
          }
        }
      }

      valkey = {
        auth = {
          password = var.langfuse_postgres_password
        }
        primary = {
          persistence = {
            storageClass = var.langfuse_postgres_storage_class != "" ? var.langfuse_postgres_storage_class : null
          }
        }
      }

      s3 = {
        auth = {
          rootPassword = var.langfuse_postgres_password
        }
        persistence = {
          storageClass = var.langfuse_postgres_storage_class != "" ? var.langfuse_postgres_storage_class : null
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
