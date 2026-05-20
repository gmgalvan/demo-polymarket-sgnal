resource "kubernetes_namespace" "nim_operator" {
  metadata {
    name = var.nim_operator_namespace
  }
}

resource "kubernetes_secret" "ngc_api_key" {
  metadata {
    name      = "ngc-api-secret"
    namespace = var.nim_operator_namespace
  }

  data = {
    NGC_API_KEY = jsondecode(data.aws_secretsmanager_secret_version.inference_api_keys.secret_string).ngc_api_key
  }

  depends_on = [kubernetes_namespace.nim_operator]
}

resource "kubernetes_secret" "ngc_api_key_examples" {
  metadata {
    name      = "ngc-api-secret"
    namespace = var.nim_examples_namespace
  }

  data = {
    NGC_API_KEY = jsondecode(data.aws_secretsmanager_secret_version.inference_api_keys.secret_string).ngc_api_key
  }
}

resource "kubernetes_secret" "ngc_registry_pull_secret_examples" {
  metadata {
    name      = "ngc-secret"
    namespace = var.nim_examples_namespace
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "nvcr.io" = {
          username = "$oauthtoken"
          password = jsondecode(data.aws_secretsmanager_secret_version.inference_api_keys.secret_string).ngc_api_key
          auth     = base64encode("$oauthtoken:${jsondecode(data.aws_secretsmanager_secret_version.inference_api_keys.secret_string).ngc_api_key}")
        }
      }
    })
  }
}

resource "helm_release" "nim_operator" {
  name       = "nim-operator"
  namespace  = var.nim_operator_namespace
  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "k8s-nim-operator"
  version    = var.nim_operator_chart_version

  set = [
    {
      name  = "tolerations[0].key"
      value = "nvidia.com/gpu"
    },
    {
      name  = "tolerations[0].operator"
      value = "Exists"
    },
    {
      name  = "tolerations[0].effect"
      value = "NoSchedule"
    }
  ]

  depends_on = [kubernetes_namespace.nim_operator]
}
