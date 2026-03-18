# ── Outputs ──────────────────────────────────────────────────────────────────

output "prometheus_endpoint" {
  description = "In-cluster Prometheus endpoint (for ServiceMonitors and dashboards)."
  value       = var.install_kube_prometheus_stack ? "http://kube-prometheus-stack-prometheus.${var.monitoring_namespace}.svc.cluster.local:9090" : null
}

output "grafana_endpoint" {
  description = "In-cluster Grafana endpoint."
  value       = var.install_kube_prometheus_stack ? "http://kube-prometheus-stack-grafana.${var.monitoring_namespace}.svc.cluster.local:80" : null
}

output "loki_endpoint" {
  description = "In-cluster Loki push endpoint (for log forwarding)."
  value       = var.install_loki_stack ? "http://loki-gateway.${var.logging_namespace}.svc.cluster.local:80" : null
}

output "otel_collector_otlp_grpc" {
  description = "OTel Collector OTLP gRPC endpoint. Pass to vLLM via --otlp-traces-endpoint."
  value       = var.install_otel_collector ? "http://otel-collector-opentelemetry-collector.${var.tracing_namespace}.svc.cluster.local:${var.otel_otlp_grpc_port}" : null
}

output "otel_collector_otlp_http" {
  description = "OTel Collector OTLP HTTP endpoint."
  value       = var.install_otel_collector ? "http://otel-collector-opentelemetry-collector.${var.tracing_namespace}.svc.cluster.local:${var.otel_otlp_http_port}" : null
}

output "langfuse_endpoint" {
  description = "In-cluster LangFuse endpoint."
  value       = var.install_langfuse ? "http://langfuse.${var.langfuse_namespace}.svc.cluster.local:3000" : null
}

output "monitoring_namespace" {
  description = "Namespace where Prometheus/Grafana are deployed."
  value       = var.monitoring_namespace
}

output "logging_namespace" {
  description = "Namespace where Loki/Fluent Bit are deployed."
  value       = var.logging_namespace
}

output "tracing_namespace" {
  description = "Namespace where OTel Collector is deployed."
  value       = var.tracing_namespace
}
