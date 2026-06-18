# External Secrets Operator Guide

Lab này dùng AWS Secrets Manager + External Secrets Operator (ESO) để sync secret
từ AWS về Kubernetes, rồi chứng minh rotate secret không cần restart pod nếu app
đọc secret qua mounted volume.

## Luồng hoạt động

```text
AWS Secrets Manager: w10/db-password
  -> ClusterSecretStore/aws-secrets-manager
  -> ExternalSecret/api-db-password
  -> Kubernetes Secret/demo/api-db-secret
  -> Deployment/demo/secret-reader mount /mnt/db/password
```

## 1. Tạo AWS resources

Mặc định Terraform trong `terraform/ec2` tạo sẵn:

- AWS Secrets Manager secret `w10/db-password`
- IAM user/access key cho ESO
- IAM policy chỉ cho phép đọc secret `w10/db-password`
- Script `generated/w10-eso-credentials.sh` để SSH vào EC2 và tạo Kubernetes
  secret `external-secrets/aws-credentials` trong Minikube cluster

Chạy:

```bash
cd terraform/ec2
terraform apply
```

Nếu muốn đổi initial password:

```hcl
eso_initial_db_password = "my-initial-password"
```

Lưu ý: secret value và IAM access key sẽ nằm trong Terraform state. Không commit
hoặc chia sẻ state.

Nếu bạn đã tạo tay secret `w10/db-password` hoặc IAM user `w10-eso` trước đó,
Terraform có thể báo resource đã tồn tại. Khi đó hãy xóa/import resource cũ,
hoặc đặt `create_eso_aws_resources = false` trong `terraform.tfvars` và dùng
phần tạo thủ công bên dưới.

## 2. Tạo AWS credentials secret trong Kubernetes

Không commit AWS credentials vào Git. Terraform tạo script local để SSH vào EC2
và đưa access key vào Kubernetes Secret trong Minikube cluster:

```bash
cd terraform/ec2
./generated/w10-eso-credentials.sh
```

Nếu bạn không dùng Terraform để tạo AWS resources, vẫn có thể tạo secret thủ
công:

```bash
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic aws-credentials -n external-secrets \
  --from-literal=access-key="$AWS_ACCESS_KEY_ID" \
  --from-literal=secret-access-key="$AWS_SECRET_ACCESS_KEY"
```

IAM user/access key cần tối thiểu quyền:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:ap-southeast-2:*:secret:w10/db-password-*"
    }
  ]
}
```

## 3. Deploy qua ArgoCD

Root app tạo 2 child apps:

- `external-secrets`: cài ESO operator và CRDs.
- `eso-config`: sync `ClusterSecretStore`, `ExternalSecret`, và demo
  `Deployment/secret-reader`.

Kiểm tra:

```bash
kubectl get application external-secrets eso-config -n argocd
kubectl get pods -n external-secrets
kubectl get clustersecretstore aws-secrets-manager
kubectl get externalsecret api-db-password -n demo
kubectl get secret api-db-secret -n demo
```

## 4. Xem pod đọc secret

```bash
kubectl logs -n demo deploy/secret-reader -f
```

Kỳ vọng log in ra:

```text
... db-password=initial-db-password
```

## 5. Rotate secret không restart pod

Đổi value trên AWS:

```bash
aws secretsmanager put-secret-value \
  --region ap-southeast-2 \
  --secret-id w10/db-password \
  --secret-string '{"password":"rotated-db-password"}'
```

ESO có `refreshInterval: 30s`. Đợi dưới 60 giây rồi kiểm tra K8s Secret:

```bash
kubectl get secret api-db-secret -n demo -o jsonpath='{.data.password}' | base64 -d; echo
```

Theo dõi lại pod:

```bash
kubectl logs -n demo deploy/secret-reader -f
```

Kỳ vọng log đổi sang:

```text
... db-password=rotated-db-password
```

Kiểm tra pod không restart:

```bash
kubectl get pod -n demo -l app=secret-reader
```

`RESTARTS` không tăng. Lý do: app đọc secret từ mounted volume, Kubernetes tự
cập nhật file trong volume khi Secret thay đổi. Nếu app đọc secret qua env var,
pod phải restart mới nhận value mới.
