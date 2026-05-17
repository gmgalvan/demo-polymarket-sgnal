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

variable "tracing_namespace" {
  description = "Namespace for the OpenTelemetry Collector."
  type        = string
  default     = "tracing"
}

variable "langfuse_namespace" {
  description = "Namespace for LangFuse."
  type        = string
  default     = "langfuse"
}

variable "otel_collector_chart_version" {
  description = "OpenTelemetry Collector Helm chart version."
  type        = string
  default     = "0.115.0"
}

variable "otel_otlp_grpc_port" {
  description = "OTLP gRPC receiver port."
  type        = number
  default     = 4317
}

variable "otel_otlp_http_port" {
  description = "OTLP HTTP receiver port."
  type        = number
  default     = 4318
}

variable "enable_service_monitor" {
  description = "Enable the collector ServiceMonitor for Prometheus scraping."
  type        = bool
  default     = true
}

variable "export_to_langfuse" {
  description = "Export traces from OTel Collector to LangFuse."
  type        = bool
  default     = true
}
