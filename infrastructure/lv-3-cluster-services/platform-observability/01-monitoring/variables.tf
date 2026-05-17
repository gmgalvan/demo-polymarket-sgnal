variable "aws_region" {
  description = "AWS region where EKS cluster is deployed."
  type        = string
  default     = "us-east-1"
}

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

variable "security_and_config_state_bucket" {
  description = "S3 bucket containing lv-1 security/config Terraform state."
  type        = string
  default     = "352-demo-dev-s3b-tfstate-backend"
}

variable "security_and_config_state_key" {
  description = "S3 key for lv-1 security/config Terraform state."
  type        = string
  default     = "dev/lv-1-security-and-config/secrets/terraform.tfstate"
}

variable "security_and_config_state_region" {
  description = "Region where lv-1 security/config state backend lives."
  type        = string
  default     = "us-east-1"
}

variable "monitoring_namespace" {
  description = "Namespace for Prometheus, Grafana, and Alertmanager."
  type        = string
  default     = "monitoring"
}

variable "logging_namespace" {
  description = "Namespace for Loki."
  type        = string
  default     = "logging"
}

variable "tracing_namespace" {
  description = "Namespace for the OpenTelemetry Collector."
  type        = string
  default     = "tracing"
}

variable "kube_prometheus_stack_chart_version" {
  description = "kube-prometheus-stack Helm chart version."
  type        = string
  default     = "72.6.2"
}

variable "prometheus_adapter_chart_version" {
  description = "prometheus-adapter Helm chart version."
  type        = string
  default     = "4.11.0"
}

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
  description = "StorageClass for Prometheus PVC. Empty string uses the cluster default."
  type        = string
  default     = "efs-sc"
}

variable "enable_loki_datasource" {
  description = "Configure Grafana with a Loki datasource."
  type        = bool
  default     = true
}

variable "enable_tempo_datasource" {
  description = "Configure Grafana with an OTel/Tempo datasource."
  type        = bool
  default     = true
}
