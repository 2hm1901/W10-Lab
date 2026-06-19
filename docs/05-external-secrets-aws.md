# 05 - External Secrets Operator Và AWS Secrets Manager

ESO lab chứng minh cách đưa secret từ AWS Secrets Manager về Kubernetes mà không
commit secret value vào Git.

## Luồng hoạt động

```text
AWS Secrets Manager: w10/db-password
  -> ClusterSecretStore/aws-secrets-manager
  -> ExternalSecret/demo/api-db-password
  -> Secret/demo/api-db-secret
  -> Deployment/demo/secret-reader
```

## Manifest chính

| File | Vai trò |
| --- | --- |
| `argocd/apps/eso.yaml` | Cài External Secrets Operator bằng Helm |
| `argocd/apps/eso-config.yaml` | Sync SecretStore, ExternalSecret, secret-reader |
| `eso/secret-store.yaml` | Cấu hình provider AWS Secrets Manager |
| `eso/external-secret.yaml` | Map AWS secret key sang Kubernetes Secret |
| `eso/secret-reader-deployment.yaml` | Pod đọc secret qua mounted volume |

## Tên app trên UI

File `argocd/apps/eso.yaml` tạo app tên:

```yaml
metadata:
  name: external-secrets
```

Vì vậy trên ArgoCD UI app là `external-secrets`, không phải `eso`.

## Secret AWS credentials

`ClusterSecretStore` cần secret:

```text
namespace: external-secrets
name: aws-credentials
keys:
  access-key
  secret-access-key
```

Terraform tạo IAM user/access key và script:

```bash
cd terraform/ec2
./generated/w10-eso-credentials.sh
```

Script SSH vào EC2 và tạo Kubernetes secret. Secret này không nằm trong Git.

## Kiểm tra ESO

```bash
kubectl -n external-secrets get secret aws-credentials
```

Secret credential cho ESO đã có chưa.

```bash
kubectl get clustersecretstore aws-secrets-manager
```

`READY=True` nghĩa là ESO dùng credential gọi AWS được.

```bash
kubectl get externalsecret api-db-password -n demo
```

ExternalSecret có sync được không.

```bash
kubectl get secret api-db-secret -n demo
```

Kubernetes Secret đích đã được tạo chưa.

```bash
kubectl logs -n demo deploy/secret-reader --tail=20
```

Pod đọc secret qua volume và in value ra log.

## Rotate secret

Chạy trên máy có AWS credentials, thường là máy local:

```bash
AWS_PAGER="" aws secretsmanager put-secret-value \
  --no-cli-pager \
  --region ap-southeast-2 \
  --secret-id w10/db-password \
  --secret-string '{"password":"rotated-db-password"}'
```

Ý nghĩa:

- `put-secret-value`: tạo version secret mới.
- `--secret-id`: tên secret AWS.
- `--secret-string`: JSON chứa field `password`.
- `AWS_PAGER=""` và `--no-cli-pager`: tránh AWS CLI mở pager làm tưởng bị treo.

Sau đó chờ ESO refresh:

```bash
kubectl get secret api-db-secret -n demo -o jsonpath='{.data.password}' | base64 -d; echo
kubectl logs -n demo deploy/secret-reader --tail=20
```

Nếu app đọc secret qua mounted volume, Kubernetes cập nhật file secret mà không
cần restart pod.

## Vì sao không dùng env var cho secret rotate

Nếu secret được inject qua env var, giá trị chỉ được set khi container start.
Rotate Kubernetes Secret không tự thay env var trong process đang chạy.

Mounted Secret volume được kubelet cập nhật định kỳ, nên phù hợp để chứng minh
rotate không restart pod.

## ArgoCD OutOfSync với ExternalSecret

ESO có thể default thêm field vào `ExternalSecret`. Vì vậy `argocd/apps/eso-config.yaml`
có `ignoreDifferences` cho các field default như:

- `/spec/refreshPolicy`
- `/spec/target/deletionPolicy`
- `/spec/target/template/engineVersion`
- remoteRef strategy fields

Đây là drift hợp lệ do controller/defaulting tạo, không phải lỗi sync thật.

## Lỗi thường gặp

`InvalidProviderConfig: secret "aws-credentials" not found`

Chưa chạy `generated/w10-eso-credentials.sh` hoặc secret tạo sai namespace.

`Unable to locate credentials` khi chạy AWS CLI trên EC2

AWS CLI shell chưa có credentials. Kubernetes secret của ESO không tự cấu hình
AWS CLI cho `ec2-user`.

`api-db-secret not found`

Kiểm tra thứ tự: AWS secret tồn tại, `aws-credentials` có, ClusterSecretStore
Ready, ExternalSecret Ready.
