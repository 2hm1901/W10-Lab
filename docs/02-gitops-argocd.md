# 02 - GitOps Và ArgoCD

GitOps nghĩa là Git giữ desired state. ArgoCD liên tục so sánh desired state
trong Git với live state trong Kubernetes, rồi sync để đưa cluster về đúng Git.

## App-of-Apps

Root app:

```text
argocd/root.yaml
  -> source.path = argocd/apps
```

`argocd/apps` chứa nhiều `Application`. Mỗi Application lại trỏ đến một thư mục
manifest hoặc Helm chart.

Ví dụ:

```yaml
spec:
  source:
    repoURL: https://github.com/2hm1901/W10-Lab.git
    path: app-api
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: demo
```

Ý nghĩa:

- `repoURL`: repo chứa desired state.
- `path`: thư mục manifest.
- `targetRevision`: branch/tag/commit.
- `destination`: cluster và namespace đích.

## Vì sao phải apply root thủ công

Bootstrap không tự apply `argocd/root.yaml` để người học thấy rõ bước chuyển từ
apply trực tiếp sang GitOps.

Chạy trên EC2:

```bash
kubectl apply -f /opt/w10/argocd/root.yaml
```

Sau đó kiểm tra:

```bash
kubectl get applications -n argocd
```

## Sync status và health status

`SYNC STATUS`:

- `Synced`: live state khớp Git.
- `OutOfSync`: live state lệch Git hoặc ArgoCD chưa apply hết.

`HEALTH STATUS`:

- `Healthy`: resource hoạt động tốt.
- `Progressing`: đang rollout hoặc controller đang xử lý.
- `Degraded`: controller báo lỗi, pod fail, rollout fail, secret thiếu.

Một app có thể `OutOfSync Healthy`: resource chạy tốt nhưng có drift. Một app có
thể `Synced Progressing`: manifest đã apply, workload chưa ready.

## Lệnh refresh và sync

```bash
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
```

Bắt ArgoCD refresh cache từ Git. Dùng khi vừa push commit mới.

```bash
kubectl -n argocd patch application api --type merge \
  -p '{"operation":{"sync":{"prune":true}}}'
```

Yêu cầu ArgoCD sync app `api` mà không cần login ArgoCD CLI.

`prune=true` nghĩa là xóa resource live không còn trong Git.

## Sync wave

Nhiều manifest có annotation:

```yaml
argocd.argoproj.io/sync-wave: "1"
```

Wave thấp chạy trước wave cao. Lab dùng wave để:

- Tạo namespace trước workload.
- Cài controller/CRD trước custom resource.
- Tạo SecretStore trước ExternalSecret.

## ignoreDifferences

Một số controller tự thêm field vào object live. Nếu ArgoCD so sánh cứng với Git
thì app sẽ OutOfSync mãi dù không có lỗi thật.

Ví dụ trong `argocd/apps/eso-config.yaml`, ArgoCD bỏ qua các field default của
`ExternalSecret`:

```yaml
ignoreDifferences:
- group: external-secrets.io
  kind: ExternalSecret
  jsonPointers:
  - /spec/refreshPolicy
```

Lab cũng dùng ignore drift cho Sigstore webhook `caBundle`.

## Debug ArgoCD app

```bash
kubectl -n argocd describe application eso-config
```

Xem operation, resource nào OutOfSync, events và message lỗi.

```bash
kubectl -n argocd describe application eso-config | sed -n '/Resources:/,/Events:/p'
```

Chỉ lấy phần resource và event, dễ đọc hơn.

```bash
kubectl get events -n argocd --sort-by=.lastTimestamp | tail -30
```

Xem event mới của ArgoCD.

## Tên app và tên file không nhất thiết giống nhau

Ví dụ `argocd/apps/eso.yaml` tạo Application tên:

```yaml
metadata:
  name: external-secrets
```

Vì vậy trên ArgoCD UI app hiện là `external-secrets`, không phải `eso`.

## Khi nào dùng ArgoCD CLI

Nếu đã login:

```bash
argocd app get api
argocd app sync api
```

Nếu chưa login, dùng `kubectl patch application` như trên. Cách này ổn cho lab
vì Application là Kubernetes CRD.
