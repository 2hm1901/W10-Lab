# Lab 2.2 - Trivy + Cosign

Lab này chứng minh chuỗi kiểm soát image trước khi chạy trong cluster:

1. GitHub Actions build image API.
2. Trivy scan image và fail pipeline nếu có CVE `HIGH` hoặc `CRITICAL`.
3. Cosign ký image digest sau khi push lên GHCR.
4. Sigstore Policy Controller verify chữ ký ở admission.
5. Namespace `demo` chỉ chạy image `ghcr.io/2hm1901/w10-api` đã được ký bởi
   workflow `.github/workflows/build-push.yml` trên branch `main`.

## Thành phần

```text
.github/workflows/build-push.yml
  build -> Trivy scan -> push -> Cosign keyless sign -> update Rollout image tag

argocd/apps/policy-controller.yaml
  cài Sigstore Policy Controller bằng Helm

argocd/apps/policies.yaml
  sync thư mục policies/

policies/cluster-image-policy.yaml
  ClusterImagePolicy verify image ghcr.io/2hm1901/w10-api*

app-common/demo-namespace.yaml
  label policy.sigstore.dev/include=true để admission policy enforce namespace demo
```

## Vì sao dùng Cosign keyless

Lab dùng Cosign keyless signing với GitHub OIDC, nên không cần tạo private key
và không cần lưu `COSIGN_PRIVATE_KEY` trong GitHub Secrets. Policy Controller
verify image bằng certificate identity:

- issuer: `https://token.actions.githubusercontent.com`
- subject:
  `https://github.com/2hm1901/W10-Lab/.github/workflows/build-push.yml@refs/heads/main`

Điểm cần nhớ: phải ký đúng image digest/tag mà Rollout đang dùng. Nếu workflow
ký image khác còn `app-api/rollout.yaml` trỏ tag cũ chưa ký, admission vẫn reject.

## Chạy trên GitHub Actions

Push thay đổi lên `main` hoặc chạy workflow thủ công:

```text
Actions -> Build and Push Image -> Run workflow
```

Workflow phải đi qua các bước:

- `Build image for vulnerability scan`
- `Scan image with Trivy`
- `Build and push Docker image`
- `Install Cosign`
- `Sign pushed image digest with Cosign keyless`
- `Update rollout.yaml with new version`

Nếu Trivy phát hiện CVE `HIGH` hoặc `CRITICAL`, workflow dừng trước khi push và
sign image. Khi đó cần sửa base image/dependency rồi chạy lại.

## Sync policy bằng ArgoCD trên EC2

Sau khi pull repo mới trên EC2 hoặc để ArgoCD tự sync từ GitHub, kiểm tra:

```bash
kubectl get applications -n argocd | grep -E 'policy-controller|policies'
kubectl get pods -n cosign-system
kubectl get clusterimagepolicy
kubectl get ns demo --show-labels
```

Kết quả mong muốn:

- app `policy-controller` Synced/Healthy
- app `policies` Synced/Healthy
- namespace `demo` có label `policy.sigstore.dev/include=true`
- có `ClusterImagePolicy/w10-api-keyless-signature`

Nếu root app đã có nhưng app mới chưa xuất hiện:

```bash
argocd app get root --hard-refresh
argocd app sync root
```

Nếu không dùng ArgoCD CLI:

```bash
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
```

## Test admission reject image chưa ký

Manifest dưới đây cố tình dùng image `ghcr.io/2hm1901/w10-api:unsigned-test`.
Vì image này match policy nhưng không có chữ ký hợp lệ từ workflow, API server
phải reject.

```bash
kubectl -n demo run unsigned-api \
  --image=ghcr.io/2hm1901/w10-api:unsigned-test \
  --restart=Never
```

Kết quả mong muốn là lỗi admission từ Policy Controller, ví dụ có nội dung liên
quan đến `signature` hoặc `no matching signatures`.

Dọn object test nếu nó được tạo:

```bash
kubectl -n demo delete pod unsigned-api --ignore-not-found
```

## Test image đã ký được chạy

Sau khi GitHub Actions build/sign thành công và commit update
`app-api/rollout.yaml`, sync app API:

```bash
argocd app get api --hard-refresh
argocd app sync api
kubectl argo rollouts get rollout api -n demo
```

Nếu Rollout tạo ReplicaSet/Pod mới thành công, policy đã verify chữ ký OK.

Kiểm tra image đang chạy:

```bash
kubectl -n demo get rollout api -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
kubectl -n demo get pods -l app=api
```

## Tắt enforce tạm thời khi cần debug

Policy Controller chỉ enforce namespace opt-in. Để tắt admission verify trong
namespace `demo`:

```bash
kubectl label namespace demo policy.sigstore.dev/include-
```

Bật lại:

```bash
kubectl label namespace demo policy.sigstore.dev/include=true --overwrite
```
