# 08 - Troubleshooting

File này gom các lỗi đã gặp trong lab và cách xử lý nhanh.

## Luôn bắt đầu bằng 4 lệnh này

```bash
kubectl get applications -n argocd
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp | tail -50
kubectl describe node w10 | sed -n '/Allocated resources:/,/Events:/p'
```

Ý nghĩa:

- App nào OutOfSync/Degraded.
- Pod nào Pending/CrashLoop/ImagePullBackOff.
- Event mới nhất nói nguyên nhân thật.
- Node còn CPU/memory để schedule pod không.

## ArgoCD app không thấy trên UI

Tên file không phải tên app. Xem `metadata.name`.

Ví dụ `argocd/apps/eso.yaml` tạo app `external-secrets`, không phải `eso`.

```bash
kubectl get applications -n argocd
```

## ArgoCD OutOfSync nhưng sync succeeded

Thường là drift do controller default/runtime fields.

Xem resource lệch:

```bash
kubectl -n argocd describe application <app-name> | sed -n '/Resources:/,/Events:/p'
```

Nếu là field controller tự quản, thêm `ignoreDifferences` vào Application.

Lab đã xử lý drift cho:

- Sigstore webhook `caBundle`.
- ESO `ExternalSecret` default fields.

## `argocd app sync` báo server address unspecified

ArgoCD CLI chưa login.

Dùng Kubernetes patch thay thế:

```bash
kubectl -n argocd patch application api --type merge \
  -p '{"operation":{"sync":{"prune":true}}}'
```

Hoặc login ArgoCD trước.

## `kubectl rollout restart rollout api` lỗi

`kubectl rollout restart` không hỗ trợ Argo Rollout CRD.

Dùng:

```bash
kubectl argo rollouts restart api -n demo
```

Hoặc:

```bash
kubectl -n demo patch rollout api --type merge \
  -p "{\"spec\":{\"restartAt\":\"$(date -Iseconds)\"}}"
```

## Pod Pending vì Insufficient CPU

Event:

```text
0/1 nodes are available: 1 Insufficient cpu
```

Xem resource:

```bash
kubectl describe node w10 | sed -n '/Allocated resources:/,/Events:/p'
```

Xử lý:

```bash
kubectl -n demo scale rollout api --replicas=2
kubectl -n payments scale deployment payments-api --replicas=0
kubectl -n demo scale deployment secret-reader --replicas=0
```

Giải pháp bền hơn: dùng `t3.xlarge` và `minikube_cpus=4`.

## Cosign chặn pod

Event:

```text
w10-api:local must be an image digest
no signatures found
```

Nguyên nhân: namespace có label `policy.sigstore.dev/include=true` nhưng image
đang chạy chưa ký hoặc là image local.

Gỡ label:

```bash
kubectl label namespace demo policy.sigstore.dev/include-
kubectl label namespace payments policy.sigstore.dev/include-
```

Chỉ bật lại sau khi GitHub Actions đã build/sign image.

## ESO báo `aws-credentials` not found

Tạo secret credentials:

```bash
cd terraform/ec2
./generated/w10-eso-credentials.sh
```

Kiểm tra:

```bash
kubectl -n external-secrets get secret aws-credentials
kubectl get clustersecretstore aws-secrets-manager
```

## AWS CLI local bị treo

Tắt pager và đặt timeout:

```bash
AWS_PAGER="" aws sts get-caller-identity --no-cli-pager \
  --cli-connect-timeout 10 \
  --cli-read-timeout 20
```

Rotate secret:

```bash
AWS_PAGER="" aws secretsmanager put-secret-value \
  --no-cli-pager \
  --region ap-southeast-2 \
  --secret-id w10/db-password \
  --secret-string '{"password":"rotated-db-password"}'
```

## Alertmanager thiếu email secret

Event:

```text
secret "alertmanager-email" not found
```

Tạo secret từ file example hoặc bỏ cấu hình email nếu không test alert email.

Secret email không commit vào Git.

## NetworkPolicy không chặn traffic

NetworkPolicy cần CNI hỗ trợ, ví dụ Calico.

Kiểm tra:

```bash
kubectl get pods -n kube-system | grep calico
```

Nếu cluster tạo trước khi bật `--cni=calico`, object NetworkPolicy vẫn tồn tại
nhưng không enforce traffic thật. Tạo lại EC2/Minikube bằng bootstrap mới.

## GitHub Actions không chạy trên repo fork

Fork có thể bị disable Actions mặc định. Vào GitHub repo:

```text
Actions -> enable workflows
```

Với GHCR, package cũng cần quyền phù hợp. Workflow dùng `GITHUB_TOKEN` với:

```yaml
permissions:
  contents: write
  packages: write
  id-token: write
```

## Kiểm tra cluster sau khi apply root

```bash
kubectl apply -f /opt/w10/argocd/root.yaml
kubectl get applications -n argocd
```

Nếu app mới không xuất hiện:

```bash
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
```
