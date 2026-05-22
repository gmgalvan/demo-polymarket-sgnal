output "instance_id" {
  value = aws_instance.server.id
}

output "public_ip" {
  value = aws_instance.server.public_ip
}

output "dashboard_local_url" {
  value = "http://127.0.0.1:${var.gateway_port}/"
}

output "ssm_port_forward_command" {
  value = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.server.id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"${var.gateway_port}\"],\"localPortNumber\":[\"${var.gateway_port}\"]}'"
}

output "gateway_token_file" {
  value = "/home/ec2-user/.openclaw-bootstrap/openclaw.env"
}

output "vllm_local_url" {
  value = "http://127.0.0.1:${var.vllm_port}/v1"
}

output "openclaw_model_ref" {
  value = "vllm/${var.vllm_served_model_name}"
}
