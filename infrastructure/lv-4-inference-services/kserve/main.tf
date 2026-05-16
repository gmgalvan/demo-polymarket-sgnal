resource "helm_release" "kserve" {
  name             = "kserve"
  namespace        = var.kserve_namespace
  create_namespace = true
  repository       = "oci://ghcr.io/kserve/charts"
  chart            = "kserve"
  version          = var.kserve_chart_version

  set = [
    {
      name  = "kserve.controller.deploymentMode"
      value = "RawDeployment"
    },
    {
      name  = "kserve.controller.gateway.ingressGateway.enableGatewayAPI"
      value = "false"
    }
  ]
}
