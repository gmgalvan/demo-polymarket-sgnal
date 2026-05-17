output "cluster_name" {
  description = "EKS cluster name."
  value       = data.terraform_remote_state.eks.outputs.cluster_name
}

output "tracing_namespace" {
  description = "Namespace where the OTel Collector is deployed."
  value       = var.tracing_namespace
}

output "otel_collector_otlp_grpc" {
  description = "OTLP gRPC endpoint."
  value       = "http://otel-collector-opentelemetry-collector.${var.tracing_namespace}.svc.cluster.local:${var.otel_otlp_grpc_port}"
}

output "otel_collector_otlp_http" {
  description = "OTLP HTTP endpoint."
  value       = "http://otel-collector-opentelemetry-collector.${var.tracing_namespace}.svc.cluster.local:${var.otel_otlp_http_port}"
}
