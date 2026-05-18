resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = var.cert_manager_namespace
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      # The cert-manager post-install startupapicheck job has been flaky in this
      # EKS demo environment and leaves the Helm release in failed status even
      # when the controller, webhook, and cainjector are healthy. We disable the
      # hook and validate readiness by checking the core pods directly.
      name  = "startupapicheck.enabled"
      value = "false"
    }
  ]
}
