resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = var.cert_manager_namespace
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]
}
