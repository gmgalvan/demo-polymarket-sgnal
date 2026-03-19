# ── Remote state: read EKS outputs from lv-2 ─────────────────────────────────
# This layer depends on the EKS cluster (lv-2) and Karpenter (lv-3/karpenter)
# being fully provisioned. It installs the full observability stack on top
# of the existing cluster.

data "terraform_remote_state" "eks" {
  backend = "s3"

  config = {
    bucket  = var.eks_state_bucket
    key     = var.eks_state_key
    region  = var.eks_state_region
    encrypt = true
  }
}

# ── Observability module ────────────────────────────────────────────────────

module "observability" {
  source = "../../modules/observability"

  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name

  # Feature flags — all enabled by default, toggle per environment
  install_kube_prometheus_stack = var.install_kube_prometheus_stack
  install_prometheus_adapter    = var.install_prometheus_adapter
  install_dcgm_exporter         = var.install_dcgm_exporter
  install_neuron_monitor        = var.install_neuron_monitor
  install_loki_stack            = var.install_loki_stack
  install_otel_collector        = var.install_otel_collector
  install_langfuse              = var.install_langfuse

  # Chart versions
  kube_prometheus_stack_chart_version = var.kube_prometheus_stack_chart_version
  prometheus_adapter_chart_version    = var.prometheus_adapter_chart_version
  dcgm_exporter_chart_version         = var.dcgm_exporter_chart_version
  loki_chart_version                  = var.loki_chart_version
  fluent_bit_chart_version            = var.fluent_bit_chart_version
  otel_collector_chart_version        = var.otel_collector_chart_version
  langfuse_chart_version              = var.langfuse_chart_version

  # Prometheus
  prometheus_retention     = var.prometheus_retention
  prometheus_storage_size  = var.prometheus_storage_size
  prometheus_storage_class = var.prometheus_storage_class
  loki_storage_class       = var.loki_storage_class

  # Grafana
  grafana_admin_password = var.grafana_admin_password

  # LangFuse
  langfuse_postgres_password      = var.langfuse_postgres_password
  langfuse_nextauth_secret        = var.langfuse_nextauth_secret
  langfuse_salt                   = var.langfuse_salt
  langfuse_postgres_storage_class = var.langfuse_postgres_storage_class

  # Namespaces
  monitoring_namespace = var.monitoring_namespace
  logging_namespace    = var.logging_namespace
  tracing_namespace    = var.tracing_namespace
  langfuse_namespace   = var.langfuse_namespace
}
