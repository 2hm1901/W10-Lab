# Deploy W10 API to EC2

Terraform này tạo một EC2 để chạy lại lab local trên AWS bằng Minikube:

- EC2 Amazon Linux 2023, mặc định `t3.large`, EBS `50GiB`
- Docker
- Minikube single-node Kubernetes cluster, bật Calico CNI để NetworkPolicy có
  hiệu lực
- `kubectl`, `helm`, `argocd`, `kubectl argo rollouts`
- ArgoCD
- Argo Rollouts controller
- kube-prometheus-stack gồm Prometheus, Alertmanager, Grafana
- W10 API Rollout, Service, ServiceMonitor, AnalysisTemplate, PrometheusRule
- AWS Secrets Manager secret và IAM user/access key cho ESO lab
- SSH key bằng `tls_private_key`
- File private key local bằng `local_sensitive_file`
- AWS key pair bằng `aws_key_pair`

User-data sẽ clone repo, build image `src/api` vào Docker daemon của Minikube, patch bản manifest bootstrap để dùng image local `w10-api:local`, rồi apply các manifest cần thiết.

## Cách dùng

```bash
cd terraform/ec2
cp terraform.tfvars.example terraform.tfvars
```

Sửa `terraform.tfvars`, đặc biệt:

```hcl
ssh_allowed_cidr = "YOUR_PUBLIC_IP/32"
lab_allowed_cidr = "YOUR_PUBLIC_IP/32"
```

Sau đó chạy:

```bash
terraform init
terraform plan
terraform apply
```

Bootstrap mất vài phút. Theo dõi log:

```bash
ssh -i generated/w10.pem ec2-user@$(terraform output -raw public_ip)
sudo tail -f /var/log/w10-bootstrap.log
```

## URL truy cập

```bash
terraform output argocd_url
terraform output api_url
terraform output prometheus_url
terraform output grafana_url
terraform output alertmanager_url
```

ArgoCD dùng user `admin`. Lấy password:

```bash
terraform output -raw argocd_initial_password_command
```

Rồi chạy command đó.

## Kiểm tra lab trên EC2

```bash
kubectl get pods -A
kubectl get rollout api -n demo
kubectl argo rollouts get rollout api -n demo
kubectl get analysisrun -n demo
kubectl get servicemonitor,prometheusrule -A
kubectl get pods -n kube-system | grep calico
curl "$(terraform output -raw api_url)"
curl "$(terraform output -raw api_url)/healthz"
curl "$(terraform output -raw api_url)/metrics"
```

Lưu ý: nếu EC2 được tạo trước khi bootstrap bật `--cni=calico`, các
NetworkPolicy trong tenant lab vẫn apply được nhưng không chặn traffic thật.
Muốn test isolation bằng NetworkPolicy, cần tạo lại cluster/EC2 với bootstrap
mới.

Thông tin nhanh sau bootstrap nằm ở `/home/ec2-user/w10-lab-info.txt`.

## ESO AWS resources

Mặc định Terraform tạo thêm:

- Secrets Manager secret `w10/db-password`
- IAM user `w10-eso`
- IAM policy chỉ cho phép đọc secret đó
- IAM access key cho External Secrets Operator
- Script local `generated/w10-eso-credentials.sh` để SSH vào EC2 và tạo
  Kubernetes secret trong Minikube cluster

Sau khi cluster và ESO operator đã chạy, tạo Kubernetes secret chứa AWS
credentials bằng script generated. Script này chạy trên máy local nơi bạn chạy
Terraform, sau đó SSH vào EC2 để thực thi `kubectl` trong Minikube cluster:

```bash
terraform output -raw eso_credentials_script
```

Copy path được in ra và chạy:

```bash
$(terraform output -raw eso_credentials_script)
```

Hoặc chạy trực tiếp:

```bash
./generated/w10-eso-credentials.sh
```

Điều kiện là SSH từ máy bạn vào EC2 vẫn được phép bởi `ssh_allowed_cidr`.

Lưu ý: IAM access key và `eso_initial_db_password` nằm trong Terraform state.
Không commit/chia sẻ state. Nếu không muốn Terraform tạo các resource này:

```hcl
create_eso_aws_resources = false
```

Nếu trước đó bạn đã tạo tay secret `w10/db-password` hoặc IAM user `w10-eso`,
Terraform có thể báo resource đã tồn tại. Khi đó hoặc xóa/import resource cũ,
hoặc đặt `create_eso_aws_resources = false` và tự quản lý credentials.

## Xóa hạ tầng

```bash
terraform destroy
```

Private key được tạo tại `terraform/ec2/generated/w10.pem`.

Lưu ý: `tls_private_key`, IAM access key và secret value lưu trong Terraform
state. Không commit hoặc chia sẻ state.
