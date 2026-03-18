# ── Remote state: read EKS outputs from lv-2 ─────────────────────────────────
# This layer depends on the EKS cluster being fully provisioned (lv-2) and
# Karpenter + device plugins being installed (lv-3). It only installs
# Kubernetes-level controllers on top of the existing cluster.

data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket  = var.eks_state_bucket
    key     = var.eks_state_key
    region  = var.eks_state_region
    encrypt = true
  }
}

# ── cert-manager ──────────────────────────────────────────────────────────────
# KServe uses admission webhooks with TLS certificates managed by cert-manager.
# Must be installed and ready BEFORE KServe — cert-manager issues the certs
# that the KServe webhook server presents to the API server.

resource "helm_release" "cert_manager" {
  count = var.install_cert_manager ? 1 : 0

  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version

  set = [
    {
      # Install CRDs (Certificate, Issuer, ClusterIssuer, etc.) together with the chart.
      # Without this, cert-manager starts but can't manage any certificate resources.
      name  = "crds.enabled"
      value = "true"
    }
  ]
}

# ── KServe ────────────────────────────────────────────────────────────────────
# KServe is a Kubernetes-native model serving framework.
# It provides InferenceService CRDs so you can deploy models declaratively:
#
#   apiVersion: serving.kserve.io/v1beta1
#   kind: InferenceService
#   metadata:
#     name: llama-3-8b
#   spec:
#     predictor:
#       model:
#         modelFormat: {name: pytorch}
#         storageUri: s3://my-bucket/llama-3-8b
#
# KServe handles: autoscaling (including scale-to-zero), canary rollouts,
# multi-model serving, and integrates with Knative for serverless inference.
# In this demo it would sit alongside vLLM as an alternative serving path.

resource "helm_release" "kserve" {
  count = var.install_kserve ? 1 : 0

  name             = "kserve"
  namespace        = var.kserve_namespace
  create_namespace = true
  repository       = "oci://ghcr.io/kserve/charts"
  chart            = "kserve"
  version          = var.kserve_chart_version

  set = [
    {
      # Serverless mode requires Knative. Set to RawDeployment to use plain
      # Kubernetes Deployments without Knative (simpler setup for the demo).
      name  = "kserve.controller.deploymentMode"
      value = "RawDeployment"
    },
    {
      # Disable the built-in ingress gateway — we use the cluster's existing
      # ALB / ingress controller instead.
      name  = "kserve.controller.gateway.ingressGateway.enableGatewayAPI"
      value = "false"
    }
  ]

  # cert-manager must be fully running before KServe tries to create its
  # Certificate and Issuer resources during webhook bootstrap.
  depends_on = [helm_release.cert_manager]
}

# ── KubeRay Operator ─────────────────────────────────────────────────────────
# KubeRay manages Ray clusters on Kubernetes via three CRDs:
#   - RayCluster:  long-lived Ray cluster (head + workers)
#   - RayJob:      one-off Ray job with automatic cluster lifecycle
#   - RayService:  Ray Serve deployment (HTTP serving with autoscaling)
#
# Use cases in this project:
#   - Distributed model fine-tuning jobs (RayJob on GPU nodes)
#   - Ray Serve as an alternative to vLLM for multi-model serving
#   - Parallel data preprocessing / batch inference pipelines
#
# Workers automatically land on GPU or Inferentia nodes via nodeSelector +
# tolerations in the RayCluster spec, using the same Karpenter NodePools
# defined in lv-3.

resource "helm_release" "kuberay_operator" {
  count = var.install_kuberay ? 1 : 0

  name             = "kuberay-operator"
  namespace        = var.kuberay_namespace
  create_namespace = true
  repository       = "https://ray-project.github.io/kuberay-helm/"
  chart            = "kuberay-operator"
  version          = var.kuberay_chart_version

  set = [
    {
      # Enable the RayService CRD (disabled by default in some chart versions).
      name  = "batchScheduler.enabled"
      value = "false"
    }
  ]
}

# ── NVIDIA NIM Operator ───────────────────────────────────────────────────────
# The NIM Operator manages NVIDIA NIM microservices — pre-optimized, containerized
# LLM inference endpoints published by NVIDIA on NGC (nvcr.io).
#
# NIM containers include: the model weights, TensorRT-LLM engine, and a
# OpenAI-compatible HTTP server. You deploy them with a NIMService CRD:
#
#   apiVersion: apps.nvidia.com/v1alpha1
#   kind: NIMService
#   metadata:
#     name: meta-llama3-8b-instruct
#   spec:
#     model:
#       nimCacheName: llama3-8b-cache
#       name: meta/llama3-8b-instruct
#       ngcAPISecret: ngc-api-secret
#
# The operator handles: pulling from NGC, model caching on PVCs, GPU
# scheduling, rolling updates, and health checks.
# Requires: NVIDIA GPU nodes (lv-3 NodePool gpu-inference) + NGC API key.

resource "kubernetes_namespace" "nim_operator" {
  count = var.install_nim_operator ? 1 : 0

  metadata {
    name = var.nim_operator_namespace
  }
}

resource "kubernetes_secret" "ngc_api_key" {
  count = var.install_nim_operator && var.ngc_api_key != "" ? 1 : 0

  metadata {
    name      = "ngc-api-secret"
    namespace = var.nim_operator_namespace
  }

  data = {
    # The NIM Operator reads this key to authenticate with nvcr.io when
    # pulling model containers and to download model weights from NGC.
    NGC_API_KEY = var.ngc_api_key
  }

  depends_on = [kubernetes_namespace.nim_operator]
}

resource "helm_release" "nim_operator" {
  count = var.install_nim_operator ? 1 : 0

  name       = "nim-operator"
  namespace  = var.nim_operator_namespace
  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "nvidia-nim-operator"
  version    = var.nim_operator_chart_version

  set = [
    {
      # Tolerate the nvidia.com/gpu:NoSchedule taint so the operator pod
      # itself can run on GPU nodes if needed (some versions require it
      # for direct device inspection). Adjust to false if you want the
      # operator on ARM core nodes instead.
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
