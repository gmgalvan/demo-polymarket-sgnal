# ── Outputs ──────────────────────────────────────────────────────────────────
# These outputs are stored in the Terraform state and can be consumed by
# downstream layers (lv-4) or application deployment scripts.

output "prometheus_endpoint" {
  description = "In-cluster Prometheus endpoint."
  value       = module.observability.prometheus_endpoint
}

output "grafana_endpoint" {
  description = "In-cluster Grafana endpoint."
  value       = module.observability.grafana_endpoint
}

output "loki_endpoint" {
  description = "In-cluster Loki push endpoint."
  value       = module.observability.loki_endpoint
}

output "otel_collector_otlp_grpc" {
  description = "OTel Collector OTLP gRPC endpoint. Pass to vLLM via --otlp-traces-endpoint."
  value       = module.observability.otel_collector_otlp_grpc
}

output "otel_collector_otlp_http" {
  description = "OTel Collector OTLP HTTP endpoint."
  value       = module.observability.otel_collector_otlp_http
}

output "langfuse_endpoint" {
  description = "In-cluster LangFuse endpoint."
  value       = module.observability.langfuse_endpoint
}

output "monitoring_namespace" {
  description = "Namespace where Prometheus/Grafana are deployed."
  value       = module.observability.monitoring_namespace
}
