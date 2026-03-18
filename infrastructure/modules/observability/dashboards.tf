# ── Grafana Dashboards ──────────────────────────────────────────────────────
# Dashboards are loaded via ConfigMaps with the label `grafana_dashboard: "1"`.
# The Grafana sidecar (enabled in kube-prometheus-stack) watches for these
# ConfigMaps and auto-imports them.
#
# Three dashboards are provided:
#   1. NVIDIA GPU — DCGM metrics (utilization, memory, temperature, power)
#   2. AWS Neuron — Inferentia/Trainium metrics (NeuronCore util, HBM, latency)
#   3. vLLM Model Serving — LLM inference metrics (TTFT, TPOT, queue, throughput)
#   4. GenAI Overview — High-level view combining GPU + LLM + cluster metrics

# ── 1. NVIDIA GPU Dashboard ────────────────────────────────────────────────

resource "kubectl_manifest" "dashboard_gpu" {
  count = var.install_kube_prometheus_stack && var.install_dcgm_exporter ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "grafana-dashboard-nvidia-gpu"
      namespace = var.monitoring_namespace
      labels = {
        grafana_dashboard = "1"
        app               = "kube-prometheus-stack-grafana"
      }
    }
    data = {
      "nvidia-gpu.json" = file("${path.module}/dashboards/nvidia-gpu.json")
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

# ── 2. AWS Neuron Dashboard ──────────────────────────────────────────────────

resource "kubectl_manifest" "dashboard_neuron" {
  count = var.install_kube_prometheus_stack && var.install_neuron_monitor ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "grafana-dashboard-aws-neuron"
      namespace = var.monitoring_namespace
      labels = {
        grafana_dashboard = "1"
        app               = "kube-prometheus-stack-grafana"
      }
    }
    data = {
      "aws-neuron.json" = file("${path.module}/dashboards/aws-neuron.json")
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

# ── 3. vLLM Model Serving Dashboard ────────────────────────────────────────

resource "kubectl_manifest" "dashboard_vllm" {
  count = var.install_kube_prometheus_stack ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "grafana-dashboard-vllm"
      namespace = var.monitoring_namespace
      labels = {
        grafana_dashboard = "1"
        app               = "kube-prometheus-stack-grafana"
      }
    }
    data = {
      "vllm-serving.json" = file("${path.module}/dashboards/vllm-serving.json")
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}

# ── 4. GenAI Overview Dashboard ─────────────────────────────────────────────

resource "kubectl_manifest" "dashboard_genai_overview" {
  count = var.install_kube_prometheus_stack ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "grafana-dashboard-genai-overview"
      namespace = var.monitoring_namespace
      labels = {
        grafana_dashboard = "1"
        app               = "kube-prometheus-stack-grafana"
      }
    }
    data = {
      "genai-overview.json" = file("${path.module}/dashboards/genai-overview.json")
    }
  })

  depends_on = [helm_release.kube_prometheus_stack]
}
