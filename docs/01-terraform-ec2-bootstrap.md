# 01 - Terraform, EC2 Và Bootstrap

Terraform trong `terraform/ec2` tạo hạ tầng AWS để chạy lab trên một EC2. EC2
sau đó dùng `user_data.sh.tftpl` để tự cài tool và dựng Minikube.

## File chính

| File | Vai trò |
| --- | --- |
| `versions.tf` | Khai báo Terraform providers |
| `variables.tf` | Biến cấu hình: region, instance type, ports, Minikube CPU |
| `main.tf` | EC2, security group, SSH key, user_data |
| `eso.tf` | AWS Secrets Manager + IAM user/access key cho ESO |
| `outputs.tf` | URL, SSH command, ArgoCD password command |
| `user_data.sh.tftpl` | Script bootstrap chạy trên EC2 |
| `terraform.tfvars.example` | Mẫu input cho người học |

## Vì sao dùng `tls` và `local`

Lab yêu cầu tạo key pair tự động:

- `tls_private_key` tạo private/public key.
- `local_sensitive_file` ghi private key ra `generated/w10.pem`.
- `aws_key_pair` upload public key lên AWS.

Lưu ý bảo mật: private key nằm trong Terraform state. Không commit hoặc chia sẻ
state.

## Biến quan trọng

```hcl
aws_region = "ap-southeast-2"
instance_type = "t3.xlarge"
minikube_cpus = 4
ssh_allowed_cidr = "YOUR_PUBLIC_IP/32"
lab_allowed_cidr = "YOUR_PUBLIC_IP/32"
```

Ý nghĩa:

- `aws_region`: region tạo EC2 và Secrets Manager.
- `instance_type`: CPU/RAM của EC2. Lab này nhiều controller nên dùng
  `t3.xlarge`.
- `minikube_cpus`: số CPU cấp cho Minikube.
- `ssh_allowed_cidr`: IP được SSH vào EC2.
- `lab_allowed_cidr`: IP được mở UI/API/Prometheus/Grafana/Alertmanager.

## Quy trình chạy

```bash
cd terraform/ec2
cp terraform.tfvars.example terraform.tfvars
```

Tạo file input thật từ mẫu. File `terraform.tfvars` không commit.

```bash
terraform init
```

Tải provider và khởi tạo working directory.

```bash
terraform plan
```

Xem Terraform sẽ tạo/sửa/xóa gì trước khi apply.

```bash
terraform apply
```

Tạo hạ tầng thật trên AWS. Nếu đổi `instance_type`, EC2 thường bị replace.

## Sau khi apply

```bash
ssh -i generated/w10.pem ec2-user@$(terraform output -raw public_ip)
```

SSH vào EC2 bằng private key Terraform tạo.

```bash
sudo tail -f /var/log/w10-bootstrap.log
```

Theo dõi bootstrap. Chưa nên test app khi log còn đang chạy hoặc có lỗi.

## Bootstrap làm gì

`user_data.sh.tftpl` cài:

- Docker
- kubectl
- Minikube
- Helm
- ArgoCD CLI
- kubectl argo rollouts plugin

Sau đó:

1. Start Minikube profile `w10` với Docker driver và Calico CNI.
2. Clone repo vào `/opt/w10`.
3. Build image `w10-api:local`.
4. Load image vào Minikube.
5. Patch manifest bootstrap để dùng image local.
6. Cài ArgoCD, Argo Rollouts, kube-prometheus-stack.
7. Apply workload cơ bản.
8. Tạo systemd services port-forward ra EC2 public IP.

## Vì sao clone repo ở `/opt/w10`

`/opt` phù hợp cho phần mềm hoặc lab assets dùng chung trên máy. Repo trong EC2
không phải workspace cá nhân chính; nó là bản clone để bootstrap, apply manifest
và chạy lệnh test.

## Output quan trọng

```bash
terraform output argocd_url
terraform output api_url
terraform output prometheus_url
terraform output grafana_url
terraform output alertmanager_url
```

In URL public của các service được port-forward.

```bash
terraform output -raw argocd_initial_password_command
```

In command lấy password admin của ArgoCD. Chạy command được in ra trên EC2.

```bash
terraform output -raw eso_credentials_script
```

In đường dẫn script tạo Kubernetes secret `external-secrets/aws-credentials`.

## ESO AWS resources trong Terraform

Terraform tạo:

- Secrets Manager secret `w10/db-password`.
- IAM user `w10-eso`.
- IAM policy chỉ cho đọc secret.
- IAM access key.
- Script `generated/w10-eso-credentials.sh`.

Sau apply, chạy script trên máy local:

```bash
cd terraform/ec2
./generated/w10-eso-credentials.sh
```

Script SSH vào EC2 và tạo Kubernetes secret trong namespace `external-secrets`.

## Lệnh kiểm tra sau bootstrap

```bash
kubectl get nodes
kubectl get pods -A
kubectl get pods -n kube-system | grep calico
```

Xác nhận cluster, pod hệ thống và Calico CNI.

```bash
cat /home/ec2-user/w10-lab-info.txt
```

File tóm tắt lệnh hữu ích được bootstrap tạo sẵn.
