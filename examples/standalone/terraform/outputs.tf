output "instance_id" {
  value = aws_instance.server.id
}

output "public_ip" {
  value = aws_instance.server.public_ip
}

output "service_url" {
  value = "http://${aws_instance.server.public_dns}:${var.server_port}/generate"
}
