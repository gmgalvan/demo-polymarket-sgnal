output "cluster_name" {
  description = "EKS cluster name."
  value       = data.terraform_remote_state.eks.outputs.cluster_name
}

output "prometheus_endpoint" {
  description = "In-cluster Prometheus endpoint."
  value       = "http://kube-prometheus-stack-prometheus.${var.monitoring_namespace}.svc.cluster.local:9090"
}

output "grafana_endpoint" {
  description = "In-cluster Grafana endpoint."
  value       = "http://kube-prometheus-stack-grafana.${var.monitoring_namespace}.svc.cluster.local:80"
}

output "monitoring_namespace" {
  description = "Namespace where Prometheus/Grafana are deployed."
  value       = var.monitoring_namespace
}
