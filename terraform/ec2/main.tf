locals {
  # Prefix dùng chung để đặt tên resource AWS và file key local.
  name_prefix                     = var.project_name
  private_key_path                = "${path.module}/generated/${var.project_name}.pem"
  eso_iam_user_name               = coalesce(var.eso_iam_user_name, "${var.project_name}-eso")
  eso_credentials_script_path     = "${path.module}/generated/${var.project_name}-eso-credentials.sh"
  eso_initial_secret_string_value = jsonencode({ password = var.eso_initial_db_password })

  # Tag tối thiểu giúp nhận diện resource do Terraform quản lý.
  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}

# Lab dùng default VPC/subnet để giảm cấu hình đầu vào cho người học.
data "aws_vpc" "default" {
  default = true
}

# Lấy danh sách subnet trong default VPC; EC2 sẽ dùng subnet đầu tiên.
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Luôn chọn Amazon Linux 2023 mới nhất để user-data có dnf, systemd và Docker
# package tương thích tốt với EC2.
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Sinh private key ngay trong Terraform theo yêu cầu lab.
# Lưu ý: private key cũng nằm trong Terraform state, nên cần bảo vệ state.
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Ghi private key ra máy local để SSH vào EC2 sau khi apply.
# File được tạo với quyền 0400 để ssh không từ chối key vì quá mở.
resource "local_sensitive_file" "private_key" {
  content              = tls_private_key.ssh.private_key_pem
  filename             = local.private_key_path
  file_permission      = "0400"
  directory_permission = "0700"
}

# Đăng public key lên AWS để EC2 chấp nhận private key vừa sinh.
resource "aws_key_pair" "this" {
  key_name   = "${local.name_prefix}-key"
  public_key = tls_private_key.ssh.public_key_openssh

  tags = local.common_tags
}

# Security group mở SSH và các cổng port-forward phục vụ lab.
# Nên giới hạn CIDR về IP cá nhân trong terraform.tfvars.
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-sg"
  description = "Allow SSH and W10 Flask API traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "ArgoCD UI"
    from_port   = var.argocd_port
    to_port     = var.argocd_port
    protocol    = "tcp"
    cidr_blocks = [var.lab_allowed_cidr]
  }

  ingress {
    description = "W10 API"
    from_port   = var.api_port
    to_port     = var.api_port
    protocol    = "tcp"
    cidr_blocks = [var.lab_allowed_cidr]
  }

  ingress {
    description = "Prometheus"
    from_port   = var.prometheus_port
    to_port     = var.prometheus_port
    protocol    = "tcp"
    cidr_blocks = [var.lab_allowed_cidr]
  }

  ingress {
    description = "Grafana"
    from_port   = var.grafana_port
    to_port     = var.grafana_port
    protocol    = "tcp"
    cidr_blocks = [var.lab_allowed_cidr]
  }

  ingress {
    description = "Alertmanager"
    from_port   = var.alertmanager_port
    to_port     = var.alertmanager_port
    protocol    = "tcp"
    cidr_blocks = [var.lab_allowed_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sg"
  })
}

# EC2 đóng vai trò máy lab: cài Docker, Minikube, ArgoCD, Argo Rollouts,
# kube-prometheus-stack và deploy API workload qua user-data.
resource "aws_instance" "app" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.app.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = true

  # Khi user_data thay đổi, Terraform sẽ thay EC2 để bootstrap chạy lại từ đầu.
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    alertmanager_port            = var.alertmanager_port
    api_port                     = var.api_port
    app_version                  = var.app_version
    argo_rollouts_chart_version  = var.argo_rollouts_chart_version
    argo_rollouts_plugin_version = var.argo_rollouts_plugin_version
    argocd_port                  = var.argocd_port
    error_rate                   = var.error_rate
    grafana_port                 = var.grafana_port
    kubernetes_version           = var.kubernetes_version
    minikube_cpus                = var.minikube_cpus
    minikube_disk_size           = var.minikube_disk_size
    minikube_memory              = var.minikube_memory
    prometheus_port              = var.prometheus_port
    prometheus_stack_version     = var.prometheus_stack_version
    repository_branch            = var.repository_branch
    repository_url               = var.repository_url
  })

  root_block_device {
    # Prometheus, image Docker và Minikube cần nhiều dung lượng hơn root disk
    # mặc định của nhiều AMI.
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lab"
  })

  depends_on = [local_sensitive_file.private_key]
}
