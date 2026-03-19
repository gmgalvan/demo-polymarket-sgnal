variable "aws_region" {
  description = "AWS region where EKS cluster is deployed."
  type        = string
  default     = "us-east-1"
}

# ── lv-2 remote state (EKS) ──────────────────────────────────────────────────

variable "eks_state_bucket" {
  description = "S3 bucket containing lv-2 EKS Terraform state."
  type        = string
  default     = "352-demo-dev-s3b-tfstate-backend"
}

variable "eks_state_key" {
  description = "S3 key for lv-2 EKS Terraform state."
  type        = string
  default     = "dev/lv-2-core-compute/eks/terraform.tfstate"
}

variable "eks_state_region" {
  description = "Region where lv-2 EKS state backend lives."
  type        = string
  default     = "us-east-1"
}

# ── Namespaces ──────────────────────────────────────────────────────────────

variable "monitoring_namespace" {
  description = "Namespace for Prometheus, Grafana, Alertmanager."
  type        = string
  default     = "monitoring"
}

variable "logging_namespace" {
  description = "Namespace for Loki and Fluent Bit."
  type        = string
  default     = "logging"
}

variable "tracing_namespace" {
  description = "Namespace for OpenTelemetry Collector."
  type        = string
  default     = "tracing"
}

variable "langfuse_namespace" {
  description = "Namespace for LangFuse."
  type        = string
  default     = "langfuse"
}

# ── Feature flags ───────────────────────────────────────────────────────────

variable "install_kube_prometheus_stack" {
  description = "Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)."
  type        = bool
  default     = true
}

variable "install_prometheus_adapter" {
  description = "Install prometheus-adapter for custom metrics HPA."
  type        = bool
  default     = true
}

variable "install_dcgm_exporter" {
  description = "Install NVIDIA DCGM Exporter for GPU metrics."
  type        = bool
  default     = true
}

variable "install_neuron_monitor" {
  description = "Install AWS Neuron Monitor for Inferentia/Trainium metrics."
  type        = bool
  default     = true
}

variable "install_loki_stack" {
  description = "Install Loki + Fluent Bit for centralized logging."
  type        = bool
  default     = true
}

variable "install_otel_collector" {
  description = "Install OpenTelemetry Collector for distributed tracing."
  type        = bool
  default     = true
}

variable "install_langfuse" {
  description = "Install LangFuse for LLM-specific observability."
  type        = bool
  default     = true
}

# ── Chart versions ──────────────────────────────────────────────────────────

variable "kube_prometheus_stack_chart_version" {
  description = "kube-prometheus-stack Helm chart version. null = latest."
  type        = string
  default     = "72.6.2"
  nullable    = true
}

variable "prometheus_adapter_chart_version" {
  description = "prometheus-adapter Helm chart version. null = latest."
  type        = string
  default     = "4.11.0"
  nullable    = true
}

variable "dcgm_exporter_chart_version" {
  description = "NVIDIA DCGM Exporter Helm chart version. null = latest."
  type        = string
  default     = "3.6.1"
  nullable    = true
}

variable "loki_chart_version" {
  description = "Loki Helm chart version. null = latest."
  type        = string
  default     = "6.29.0"
  nullable    = true
}

variable "fluent_bit_chart_version" {
  description = "Fluent Bit Helm chart version. null = latest."
  type        = string
  default     = "0.49.1"
  nullable    = true
}

variable "otel_collector_chart_version" {
  description = "OpenTelemetry Collector Helm chart version. null = latest."
  type        = string
  default     = "0.115.0"
  nullable    = true
}

variable "langfuse_chart_version" {
  description = "LangFuse Helm chart version. null = latest."
  type        = string
  default     = "1.2.18"
  nullable    = true
}

# ── Prometheus ──────────────────────────────────────────────────────────────

variable "prometheus_retention" {
  description = "Prometheus data retention period."
  type        = string
  default     = "5h"
}

variable "prometheus_storage_size" {
  description = "PVC size for Prometheus TSDB."
  type        = string
  default     = "50Gi"
}

variable "prometheus_storage_class" {
  description = "StorageClass for Prometheus PVC. Empty = cluster default."
  type        = string
  default     = "gp2"
}

variable "loki_storage_class" {
  description = "StorageClass for Loki PVC. Empty = cluster default."
  type        = string
  default     = "gp2"
}

# ── Grafana ─────────────────────────────────────────────────────────────────

variable "grafana_admin_password" {
  description = "Grafana admin password."
  type        = string
  sensitive   = true
  default     = "prom-operator"
}

# ── LangFuse ────────────────────────────────────────────────────────────────

variable "langfuse_postgres_password" {
  description = "Password for the LangFuse PostgreSQL database."
  type        = string
  sensitive   = true
  default     = "langfuse-dev-password"
}

variable "langfuse_nextauth_secret" {
  description = "NextAuth secret for LangFuse session encryption."
  type        = string
  sensitive   = true
  default     = "langfuse-nextauth-secret-change-me"
}

variable "langfuse_salt" {
  description = "Salt for LangFuse API key hashing."
  type        = string
  sensitive   = true
  default     = "langfuse-salt-change-me"
}

variable "langfuse_postgres_storage_class" {
  description = "StorageClass for the bundled LangFuse PostgreSQL PVC. Empty = cluster default."
  type        = string
  default     = "gp2"
}
