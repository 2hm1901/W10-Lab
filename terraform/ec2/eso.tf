# Optional AWS resources for the External Secrets Operator lab.
#
# This creates:
# - AWS Secrets Manager secret: var.eso_secret_name
# - IAM user and inline policy that can read only that secret
# - IAM access key for ESO
# - A local helper script that SSHs to EC2 and creates the Kubernetes secret
#   expected by eso/secret-store.yaml
#
# Security note: the secret value and IAM access key are stored in Terraform state.
# For real environments, prefer a remote encrypted backend and short-lived/role-based auth.
resource "aws_secretsmanager_secret" "eso_db_password" {
  # count giúp bật/tắt toàn bộ phần AWS resources cho ESO bằng một biến. Khi
  # false, các resource có index [0] sẽ không tồn tại nên output dùng try().
  count       = var.create_eso_aws_resources ? 1 : 0
  name        = var.eso_secret_name
  description = "W10 lab database password synced by External Secrets Operator"
  # recovery_window_in_days = 0 cho phép destroy xóa ngay secret trong lab. Với
  # môi trường thật nên dùng recovery window để tránh xóa nhầm.
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name = var.eso_secret_name
  })
}

resource "aws_secretsmanager_secret_version" "eso_db_password" {
  # Secret value là JSON {"password":"..."} để eso/external-secret.yaml đọc
  # remoteRef.property = password.
  count         = var.create_eso_aws_resources ? 1 : 0
  secret_id     = aws_secretsmanager_secret.eso_db_password[0].id
  secret_string = local.eso_initial_secret_string_value
}

resource "aws_iam_user" "eso" {
  # Lab dùng IAM user/access key vì chạy Minikube trên EC2 chứ không dùng IRSA
  # như EKS. Đây là cách đơn giản để minh họa ESO với AWS Secrets Manager.
  count = var.create_eso_aws_resources ? 1 : 0
  name  = local.eso_iam_user_name

  tags = merge(local.common_tags, {
    Name = local.eso_iam_user_name
  })
}

resource "aws_iam_user_policy" "eso_read_secret" {
  count = var.create_eso_aws_resources ? 1 : 0
  name  = "${local.eso_iam_user_name}-read-${replace(var.project_name, "_", "-")}-secret"
  user  = aws_iam_user.eso[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        # Quyền tối thiểu cho ESO lab: chỉ đọc và describe đúng secret do
        # Terraform tạo. Không cấp PutSecretValue để access key này không rotate
        # hoặc ghi đè secret.
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.eso_db_password[0].arn
      }
    ]
  })
}

resource "aws_iam_access_key" "eso" {
  # Secret access key chỉ hiện khi tạo; Terraform lưu nó trong state và truyền
  # vào local_sensitive_file bên dưới.
  count = var.create_eso_aws_resources ? 1 : 0
  user  = aws_iam_user.eso[0].name
}

resource "local_sensitive_file" "eso_credentials_script" {
  count = var.create_eso_aws_resources ? 1 : 0

  # File được đánh dấu sensitive để Terraform CLI không in nội dung access key.
  # Tuy vậy nội dung vẫn nằm trong state, nên state cần được bảo vệ.
  filename             = local.eso_credentials_script_path
  file_permission      = "0700"
  directory_permission = "0700"
  content = join("\n", [
    "#!/bin/sh",
    "set -eu",
    "",
    "EC2_HOST='ec2-user@${aws_instance.app.public_ip}'",
    "SSH_KEY='${local.private_key_path}'",
    "",
    "echo \"Creating external-secrets/aws-credentials on $EC2_HOST\"",
    # Script SSH vào EC2 vì kubeconfig/Minikube context nằm trên EC2. Laptop
    # chạy Terraform thường không có kubeconfig của cluster này.
    "ssh -i \"$SSH_KEY\" -o StrictHostKeyChecking=accept-new \"$EC2_HOST\" \\",
    "  AWS_ACCESS_KEY_ID='${aws_iam_access_key.eso[0].id}' \\",
    "  AWS_SECRET_ACCESS_KEY='${aws_iam_access_key.eso[0].secret}' \\",
    "  sh -s <<'REMOTE_SCRIPT'",
    "kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -",
    "kubectl create secret generic aws-credentials -n external-secrets \\",
    "  --from-literal=access-key=\"$AWS_ACCESS_KEY_ID\" \\",
    "  --from-literal=secret-access-key=\"$AWS_SECRET_ACCESS_KEY\" \\",
    "  --dry-run=client -o yaml | kubectl apply -f -",
    "REMOTE_SCRIPT",
    "",
  ])
}
