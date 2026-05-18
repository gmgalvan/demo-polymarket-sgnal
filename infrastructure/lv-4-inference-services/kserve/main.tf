resource "helm_release" "kserve_crd" {
  name             = "kserve-crd"
  namespace        = var.kserve_namespace
  create_namespace = true
  repository       = "oci://ghcr.io/kserve/charts"
  chart            = "kserve-crd"
  version          = var.kserve_chart_version
}

resource "helm_release" "kserve" {
  name             = "kserve"
  namespace        = var.kserve_namespace
  create_namespace = true
  repository       = "oci://ghcr.io/kserve/charts"
  chart            = "kserve"
  version          = var.kserve_chart_version

  depends_on = [helm_release.kserve_crd]

  set = [
    {
      name  = "kserve.controller.deploymentMode"
      value = "RawDeployment"
    },
    {
      name  = "kserve.controller.gateway.ingressGateway.enableGatewayAPI"
      value = "false"
    },
    {
      # The upstream chart defaults this sidecar to
      # gcr.io/kubebuilder/kube-rbac-proxy:v0.13.1, which is no longer
      # pullable in this environment. Override it to a currently available
      # image so the controller deployment can become healthy.
      name  = "kserve.controller.rbacProxyImage"
      value = "quay.io/brancz/kube-rbac-proxy:v0.13.1"
    }
  ]
}
