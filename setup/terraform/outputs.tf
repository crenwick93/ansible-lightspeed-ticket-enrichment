output "instance_public_ip" {
  description = "Public IP of the monitoring EC2 instance"
  value       = aws_instance.monitoring.public_ip
}

output "prometheus_url" {
  description = "Prometheus web UI"
  value       = "http://${aws_instance.monitoring.public_ip}:9090"
}

output "alertmanager_url" {
  description = "AlertManager web UI"
  value       = "http://${aws_instance.monitoring.public_ip}:9093"
}

output "hello_world_url" {
  description = "httpd hello-world page"
  value       = "http://${aws_instance.monitoring.public_ip}"
}

output "ssh_command" {
  description = "SSH into the instance"
  value       = "ssh -i ${var.private_key_path} ec2-user@${aws_instance.monitoring.public_ip}"
}
