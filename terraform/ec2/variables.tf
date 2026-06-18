variable "aws_region" {
  description = "AWS region where the EC2 instance will be created."
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Name used for AWS resource tags and generated key files."
  type        = string
  default     = "w10"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.large"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB. Minikube, images, and Prometheus need more space than the default."
  type        = number
  default     = 50
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to SSH into the instance. Replace the default with your public IP CIDR for better security."
  type        = string
  default     = "0.0.0.0/0"
}

variable "lab_allowed_cidr" {
  description = "CIDR allowed to access exposed lab ports: ArgoCD, API, Prometheus, Grafana, and Alertmanager."
  type        = string
  default     = "0.0.0.0/0"
}

variable "argocd_port" {
  description = "EC2 port that forwards to the ArgoCD server."
  type        = number
  default     = 8080
}

variable "api_port" {
  description = "EC2 port that forwards to the W10 API service."
  type        = number
  default     = 8081
}

variable "prometheus_port" {
  description = "EC2 port that forwards to Prometheus."
  type        = number
  default     = 9090
}

variable "grafana_port" {
  description = "EC2 port that forwards to Grafana."
  type        = number
  default     = 3000
}

variable "alertmanager_port" {
  description = "EC2 port that forwards to Alertmanager."
  type        = number
  default     = 9093
}

variable "repository_url" {
  description = "Git repository URL cloned on EC2 for local manifest bootstrap and API image build."
  type        = string
  default     = "https://github.com/2hm1901/W10-Lab.git"
}

variable "repository_branch" {
  description = "Git branch cloned on EC2."
  type        = string
  default     = "main"
}

variable "app_version" {
  description = "VERSION environment variable passed to the Flask API."
  type        = string
  default     = "ec2"
}

variable "error_rate" {
  description = "ERROR_RATE environment variable passed to the Flask API."
  type        = string
  default     = "0"
}

variable "kubernetes_version" {
  description = "Kubernetes version for Minikube."
  type        = string
  default     = "v1.31.0"
}

variable "minikube_cpus" {
  description = "CPU cores allocated to Minikube."
  type        = number
  default     = 2
}

variable "minikube_memory" {
  description = "Memory allocated to Minikube, for example 6144mb."
  type        = string
  default     = "6144mb"
}

variable "minikube_disk_size" {
  description = "Disk size allocated to Minikube."
  type        = string
  default     = "35g"
}

variable "prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version used by the lab manifests."
  type        = string
  default     = "65.1.1"
}

variable "argo_rollouts_chart_version" {
  description = "Argo Rollouts Helm chart version used by the lab manifests."
  type        = string
  default     = "2.37.7"
}

variable "argo_rollouts_plugin_version" {
  description = "kubectl argo rollouts plugin version."
  type        = string
  default     = "1.7.2"
}

variable "create_eso_aws_resources" {
  description = "Create AWS Secrets Manager secret and IAM access key for External Secrets Operator."
  type        = bool
  default     = true
}

variable "eso_secret_name" {
  description = "AWS Secrets Manager secret name used by the ESO lab."
  type        = string
  default     = "w10/db-password"
}

variable "eso_initial_db_password" {
  description = "Initial password value stored in AWS Secrets Manager for the ESO lab."
  type        = string
  sensitive   = true
  default     = "initial-db-password"
}

variable "eso_iam_user_name" {
  description = "Optional IAM user name for ESO. If null, project_name-eso is used."
  type        = string
  default     = null
}
