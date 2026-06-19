output "instance_id" {
  # Dùng khi cần tra EC2 trong AWS console hoặc debug terraform state.
  description = "EC2 instance ID."
  value       = aws_instance.app.id
}

output "public_ip" {
  # Public IP thay đổi khi EC2 bị replace. Luôn lấy lại output sau terraform
  # apply thay vì dùng IP cũ.
  description = "Public IP of the EC2 instance."
  value       = aws_instance.app.public_ip
}

output "argocd_url" {
  # URL public đi vào systemd port-forward service trên EC2, không phải Service
  # type LoadBalancer.
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
  # In sẵn command để tránh nhập sai key path hoặc public IP sau khi EC2 replace.
  description = "SSH command for the EC2 instance."
  value       = "ssh -i ${local.private_key_path} ec2-user@${aws_instance.app.public_ip}"
}

output "argocd_initial_password_command" {
  # Password admin được ArgoCD sinh trong Kubernetes Secret. Command này SSH vào
  # EC2 rồi đọc secret bằng kubectl tại đúng kubeconfig Minikube.
  description = "Command to retrieve the ArgoCD admin password from the EC2 instance."
  value       = "ssh -i ${local.private_key_path} ec2-user@${aws_instance.app.public_ip} 'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d; echo'"
}

output "private_key_path" {
  # Mark sensitive để Terraform không in key path trong một số context output
  # nhạy cảm; private key content đã nằm trong local_sensitive_file và state.
  description = "Local path to the generated private key."
  value       = local.private_key_path
  sensitive   = true
}

output "eso_secret_arn" {
  # try(..., null) giúp output vẫn hợp lệ khi create_eso_aws_resources=false.
  description = "ARN of the AWS Secrets Manager secret used by the ESO lab."
  value       = try(aws_secretsmanager_secret.eso_db_password[0].arn, null)
}

output "eso_iam_user_name" {
  # Trả null nếu Terraform không quản lý IAM user cho ESO.
  description = "IAM user created for ESO to read the lab secret."
  value       = try(aws_iam_user.eso[0].name, null)
}

output "eso_credentials_script" {
  # Sensitive vì script chứa IAM access key secret. Dùng:
  # terraform output -raw eso_credentials_script
  description = "Local script that SSHs to EC2 and creates the Kubernetes aws-credentials secret for ESO."
  value       = var.create_eso_aws_resources ? local.eso_credentials_script_path : null
  sensitive   = true
}
