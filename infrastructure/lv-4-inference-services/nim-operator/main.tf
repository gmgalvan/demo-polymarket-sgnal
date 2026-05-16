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
    NGC_API_KEY = var.ngc_api_key
  }

  depends_on = [kubernetes_namespace.nim_operator]
}

resource "helm_release" "nim_operator" {
  name       = "nim-operator"
  namespace  = var.nim_operator_namespace
  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "nvidia-nim-operator"
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
