locals {
  arm_ami_ssm_parameter = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2023/arm64/standard/recommended/image_id"
  gpu_ami_ssm_parameter = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2023/x86_64/nvidia/recommended/image_id"
  inf_ami_ssm_parameter = "/aws/service/eks/optimized-ami/${var.cluster_version}/amazon-linux-2023/x86_64/neuron/recommended/image_id"
}

# ── Karpenter controller ─────────────────────────────────────────────────────

resource "helm_release" "karpenter_crd" {
  name             = "karpenter-crd"
  namespace        = var.karpenter_namespace
  create_namespace = false
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter-crd"
  version          = var.karpenter_chart_version

  wait    = true
  timeout = 900
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = var.karpenter_namespace
  create_namespace = false
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_chart_version

  wait    = true
  timeout = 900

  set = [
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = var.karpenter_iam_role_arn
    },
    {
      name  = "settings.clusterName"
      value = var.cluster_name
    },
    {
      name  = "settings.clusterEndpoint"
      value = var.cluster_endpoint
    },
    {
      name  = "settings.interruptionQueue"
      value = var.karpenter_interruption_queue_name
    }
  ]

  depends_on = [helm_release.karpenter_crd]
}

# ── Device plugins ───────────────────────────────────────────────────────────

resource "helm_release" "nvidia_device_plugin" {
  count            = var.install_nvidia_device_plugin ? 1 : 0
  name             = "nvidia-device-plugin"
  namespace        = "kube-system"
  create_namespace = false
  repository       = "https://nvidia.github.io/k8s-device-plugin"
  chart            = "nvidia-device-plugin"

  values = [
    yamlencode({
      affinity = {
        nodeAffinity = {
          requiredDuringSchedulingIgnoredDuringExecution = {
            nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key      = "workload"
                    operator = "In"
                    values   = ["gpu"]
                  }
                ]
              }
            ]
          }
        }
      }
      gfd = {
        enabled = false
      }
      nodeSelector = {
        workload = "gpu"
      }
      tolerations = [
        {
          key      = "nvidia.com/gpu"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      ]
    })
  ]

  depends_on = [helm_release.karpenter]
}

resource "helm_release" "neuron_device_plugin" {
  count            = var.install_neuron_device_plugin ? 1 : 0
  name             = "neuron-device-plugin"
  namespace        = "kube-system"
  create_namespace = false
  repository       = "oci://public.ecr.aws/neuron"
  chart            = "neuron-helm-chart"

  set = [
    {
      name  = "npd.enabled"
      value = "false"
    }
  ]

  depends_on = [helm_release.karpenter]
}
