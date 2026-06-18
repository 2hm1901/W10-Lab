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

output "eso_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret used by the ESO lab."
  value       = try(aws_secretsmanager_secret.eso_db_password[0].arn, null)
}

output "eso_iam_user_name" {
  description = "IAM user created for ESO to read the lab secret."
  value       = try(aws_iam_user.eso[0].name, null)
}

output "eso_credentials_script" {
  description = "Local script that SSHs to EC2 and creates the Kubernetes aws-credentials secret for ESO."
  value       = var.create_eso_aws_resources ? local.eso_credentials_script_path : null
  sensitive   = true
}
