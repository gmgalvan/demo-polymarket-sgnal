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
            value = jsondecode(data.aws_secretsmanager_secret_version.langfuse_nextauth_secret.secret_string).secret
          }
          url = "http://langfuse.${var.langfuse_namespace}.svc.cluster.local:3000"
        }

        salt = {
          value = jsondecode(data.aws_secretsmanager_secret_version.langfuse_salt.secret_string).salt
        }

        telemetry = {
          enabled = false
        }
      }

      postgresql = {
        enabled = true
        auth = {
          password = jsondecode(data.aws_secretsmanager_secret_version.langfuse_postgres_password.secret_string).password
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
          password = jsondecode(data.aws_secretsmanager_secret_version.langfuse_postgres_password.secret_string).password
        }
        persistence = {
          storageClass = var.langfuse_postgres_storage_class != "" ? var.langfuse_postgres_storage_class : null
        }
      }

      redis = {
        auth = {
          password = jsondecode(data.aws_secretsmanager_secret_version.langfuse_postgres_password.secret_string).password
        }
        master = {
          persistence = {
            storageClass = var.langfuse_postgres_storage_class != "" ? var.langfuse_postgres_storage_class : null
          }
        }
      }

      valkey = {
        auth = {
          password = jsondecode(data.aws_secretsmanager_secret_version.langfuse_postgres_password.secret_string).password
        }
        primary = {
          persistence = {
            storageClass = var.langfuse_postgres_storage_class != "" ? var.langfuse_postgres_storage_class : null
          }
        }
      }

      s3 = {
        auth = {
          rootPassword = jsondecode(data.aws_secretsmanager_secret_version.langfuse_postgres_password.secret_string).password
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
