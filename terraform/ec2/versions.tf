terraform {
  # Terraform 1.5+ đủ mới cho các provider/resource dùng trong lab và vẫn phổ
  # biến trên máy local của người học.
  required_version = ">= 1.5.0"

  required_providers {
    # AWS provider tạo EC2, security group, key pair, IAM và Secrets Manager.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # TLS provider sinh SSH key pair ngay trong Terraform theo yêu cầu lab.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # Local provider ghi private key và helper script ra máy chạy Terraform.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  # Toàn bộ AWS resources của lab được tạo trong cùng region để tránh nhầm ARN,
  # endpoint Secrets Manager và AMI lookup.
  region = var.aws_region
}
