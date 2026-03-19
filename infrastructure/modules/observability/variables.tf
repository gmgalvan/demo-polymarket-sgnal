# ── General ──────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "EKS cluster name. Used for labeling and dashboard titles."
  type        = string
}

variable "monitoring_namespace" {
  description = "Namespace for Prometheus, Grafana, and alerting components."
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
  description = "Namespace for LangFuse LLM observability."
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
  description = "Install prometheus-adapter for custom/external metrics HPA."
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
  description = "Install LangFuse for LLM-specific observability (prompt tracing, token usage)."
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
  description = "Loki Helm chart version (grafana/loki). null = latest."
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

# ── Prometheus configuration ────────────────────────────────────────────────

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
  description = "StorageClass for Prometheus PVC. Empty string = cluster default."
  type        = string
  default     = ""
}

variable "loki_storage_class" {
  description = "StorageClass for Loki PVC. Empty string = cluster default."
  type        = string
  default     = ""
}

# ── Grafana ─────────────────────────────────────────────────────────────────

variable "grafana_admin_password" {
  description = "Grafana admin password. Use a secret manager in production."
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
  description = "StorageClass for the bundled LangFuse PostgreSQL PVC. Empty string = cluster default."
  type        = string
  default     = ""
}

# ── OTel Collector ──────────────────────────────────────────────────────────

variable "otel_otlp_grpc_port" {
  description = "OTLP gRPC receiver port on the OTel Collector."
  type        = number
  default     = 4317
}

variable "otel_otlp_http_port" {
  description = "OTLP HTTP receiver port on the OTel Collector."
  type        = number
  default     = 4318
}
