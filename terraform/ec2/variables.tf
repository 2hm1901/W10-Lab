variable "aws_region" {
  # Region phải khớp với nơi bạn muốn tạo EC2 và nơi ESO đọc AWS Secrets
  # Manager. Lab đang dùng Sydney: ap-southeast-2.
  description = "AWS region where the EC2 instance will be created."
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  # Prefix dùng cho tên resource AWS và file generated như generated/w10.pem.
  description = "Name used for AWS resource tags and generated key files."
  type        = string
  default     = "w10"
}

variable "instance_type" {
  # t3.xlarge đủ CPU hơn cho ArgoCD, Prometheus, Gatekeeper, ESO, Policy
  # Controller, Calico và payments tenant cùng chạy trên một node Minikube.
  description = "EC2 instance type."
  type        = string
  default     = "t3.xlarge"
}

variable "root_volume_size" {
  # Docker images, Minikube disk, Prometheus data và Helm artifacts có thể nhanh
  # chóng vượt root disk mặc định của AMI.
  description = "Root EBS volume size in GiB. Minikube, images, and Prometheus need more space than the default."
  type        = number
  default     = 50
}

variable "ssh_allowed_cidr" {
  # Nên đặt YOUR_PUBLIC_IP/32 thay vì 0.0.0.0/0 để không mở SSH cho Internet.
  description = "CIDR allowed to SSH into the instance. Replace the default with your public IP CIDR for better security."
  type        = string
  default     = "0.0.0.0/0"
}

variable "lab_allowed_cidr" {
  # Các UI lab được expose qua EC2 public IP bằng systemd port-forward services.
  # Giới hạn CIDR về IP cá nhân để tránh ai cũng vào được ArgoCD/Grafana.
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
  # EC2 bootstrap clone repo này vào /opt/w10 để build image local và apply
  # manifest. Khi fork/đổi repo, cập nhật biến này.
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
  # Giá trị VERSION cho API bootstrap local, giúp phân biệt response khi test.
  description = "VERSION environment variable passed to the Flask API."
  type        = string
  default     = "ec2"
}

variable "error_rate" {
  # ERROR_RATE dùng để giả lập HTTP 500 trong Flask API khi test canary/alert.
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
  # Giá trị này không được lớn hơn số vCPU thực tế của EC2. Với t3.xlarge có 4
  # vCPU nên lab cấp 4 CPU cho Minikube.
  description = "CPU cores allocated to Minikube."
  type        = number
  default     = 4
}

variable "minikube_memory" {
  # Nếu tăng instance type lớn hơn, có thể tăng memory để Prometheus/Gatekeeper
  # ít bị eviction hơn.
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
  # Bật để Terraform tạo Secrets Manager secret + IAM user/access key cho ESO.
  # Tắt nếu bạn muốn tự quản lý AWS secret/IAM hoặc resource đã tồn tại.
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
  # Sensitive chỉ che output CLI; giá trị vẫn nằm trong Terraform state. Không
  # commit hoặc chia sẻ state.
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
