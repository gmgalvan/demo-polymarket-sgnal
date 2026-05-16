resource "helm_release" "kuberay_operator" {
  name             = "kuberay-operator"
  namespace        = var.kuberay_namespace
  create_namespace = true
  repository       = "https://ray-project.github.io/kuberay-helm/"
  chart            = "kuberay-operator"
  version          = var.kuberay_chart_version

  set = [
    {
      name  = "batchScheduler.enabled"
      value = "false"
    }
  ]
}
