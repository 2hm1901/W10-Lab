# 06 - Trivy, Cosign Và Sigstore Policy Controller

Lab này thêm supply-chain security: image phải được scan sạch CVE nghiêm trọng
và được ký trước khi admission cho chạy.

## CI workflow

File:

```text
.github/workflows/build-push.yml
```

Luồng:

```text
checkout
  -> calculate semantic version
  -> docker login GHCR
  -> build image local for scan
  -> Trivy scan HIGH/CRITICAL
  -> build and push image
  -> Cosign keyless sign image digest
  -> update app-api/rollout.yaml
  -> commit tag/version update
```

## Trivy

Workflow dùng:

```yaml
uses: aquasecurity/trivy-action@0.28.0
with:
  exit-code: '1'
  ignore-unfixed: true
  vuln-type: os,library
  severity: HIGH,CRITICAL
```

Ý nghĩa:

- Fail pipeline nếu có CVE `HIGH` hoặc `CRITICAL`.
- Scan cả OS package và library dependency.
- Bỏ qua CVE chưa có bản vá bằng `ignore-unfixed`.

## Cosign keyless

Workflow cấp quyền:

```yaml
permissions:
  id-token: write
  packages: write
```

`id-token: write` cho GitHub Actions lấy OIDC token. Cosign dùng token này để
ký keyless qua Sigstore/Fulcio, không cần private key.

Lệnh ký:

```bash
cosign sign --yes "ghcr.io/2hm1901/w10-api@${DIGEST}"
```

Ký theo digest, không chỉ tag. Tag có thể trỏ sang digest khác, còn digest là
content-addressed immutable reference.

## Policy Controller

Files:

- `argocd/apps/policy-controller.yaml`
- `argocd/apps/policies.yaml`
- `policies/cluster-image-policy.yaml`

`ClusterImagePolicy` yêu cầu image `ghcr.io/2hm1901/w10-api*` có chữ ký từ
workflow GitHub Actions của repo:

```yaml
issuer: https://token.actions.githubusercontent.com
subject: https://github.com/2hm1901/W10-Lab/.github/workflows/build-push.yml@refs/heads/main
```

## Vì sao enforce là opt-in

Policy Controller chỉ enforce namespace có label:

```bash
policy.sigstore.dev/include=true
```

Repo không bật label này mặc định vì bootstrap EC2 dùng image local
`w10-api:local`, và image GHCR chỉ verify được sau khi GitHub Actions build/sign
thành công.

Nếu bật quá sớm, bạn sẽ thấy lỗi:

```text
w10-api:local must be an image digest
no signatures found
```

## Kiểm tra controller và policy

```bash
kubectl get pods -n cosign-system
```

Policy Controller webhook phải Running.

```bash
kubectl get clusterimagepolicy
```

Policy `w10-api-keyless-signature` phải tồn tại.

```bash
kubectl get applications -n argocd | grep -E 'policy-controller|policies'
```

Hai ArgoCD app phải Synced/Healthy hoặc ít nhất Healthy.

## Test unsigned image bị chặn

```bash
kubectl label namespace demo policy.sigstore.dev/include=true --overwrite
```

Bật enforce cho namespace `demo`.

```bash
kubectl -n demo run unsigned-api \
  --image=ghcr.io/2hm1901/w10-api:unsigned-test \
  --restart=Never
```

Kỳ vọng: API server reject vì image chưa ký.

Nếu vẫn dùng image local hoặc image chưa ký, gỡ label sau test:

```bash
kubectl label namespace demo policy.sigstore.dev/include-
```

## Test signed image chạy được

1. Chạy GitHub Actions `Build and Push Image`.
2. Chờ Trivy pass và Cosign sign pass.
3. Pull Git trên EC2:

```bash
cd /opt/w10
git pull
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
```

4. Bật enforce:

```bash
kubectl label namespace demo policy.sigstore.dev/include=true --overwrite
```

5. Sync API:

```bash
kubectl -n argocd patch application api --type merge \
  -p '{"operation":{"sync":{"prune":true}}}'
```

Nếu pod mới tạo được, chữ ký verify OK.

## Debug Policy Controller

```bash
kubectl -n cosign-system logs deploy/policy-controller-webhook --tail=100
```

Xem lỗi verify.

```bash
kubectl get events -n demo --sort-by=.lastTimestamp | tail -30
```

Xem admission rejection message.

## Drift ArgoCD

Policy Controller chart tự quản lý webhook CA bundle. `policy-controller` app có
`ignoreDifferences` để bỏ qua `clientConfig.caBundle`, tránh OutOfSync vô hạn.
