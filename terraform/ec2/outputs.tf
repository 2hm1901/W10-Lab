output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Public IP of the EC2 instance."
  value       = aws_instance.app.public_ip
}

output "argocd_url" {
  description = "URL for the ArgoCD UI."
  value       = "https://${aws_instance.app.public_ip}:${var.argocd_port}"
}

output "api_url" {
  description = "URL for the W10 API."
  value       = "http://${aws_instance.app.public_ip}:${var.api_port}"
}

output "prometheus_url" {
  description = "URL for Prometheus."
  value       = "http://${aws_instance.app.public_ip}:${var.prometheus_port}"
}

output "grafana_url" {
  description = "URL for Grafana."
  value       = "http://${aws_instance.app.public_ip}:${var.grafana_port}"
}

output "alertmanager_url" {
  description = "URL for Alertmanager."
  value       = "http://${aws_instance.app.public_ip}:${var.alertmanager_port}"
}

output "ssh_command" {
  description = "SSH command for the EC2 instance."
  value       = "ssh -i ${local.private_key_path} ec2-user@${aws_instance.app.public_ip}"
}

output "argocd_initial_password_command" {
  description = "Command to retrieve the ArgoCD admin password from the EC2 instance."
  value       = "ssh -i ${local.private_key_path} ec2-user@${aws_instance.app.public_ip} 'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d; echo'"
}

output "private_key_path" {
  description = "Local path to the generated private key."
  value       = local.private_key_path
  sensitive   = true
}
