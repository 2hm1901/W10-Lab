# Gatekeeper Guide

Lab này cài OPA Gatekeeper qua GitOps và enforce 5 luật admission trong namespace
`demo`.

| # | Luật | Risk |
| --- | --- | --- |
| 1 | Cấm image tag `:latest` | F-01 |
| 2 | Bắt buộc có `resources.limits.cpu` và `resources.limits.memory` | F-02 |
| 3 | Cấm `runAsUser: 0` | F-04 |
| 4 | Cấm `hostNetwork: true` | - |
| 5 | Cấm `Deployment.spec.replicas > 5` | - |

## Deploy qua ArgoCD

Root app sẽ tạo 2 child apps:

- `gatekeeper`: cài controller và CRDs từ Helm chart.
- `gatekeeper-constraints`: sync `ConstraintTemplate` và `Constraint`.

Nếu root app đã được apply, sync lại root hoặc chờ ArgoCD tự sync:

```bash
kubectl get applications -n argocd
```

Kiểm tra controller:

```bash
kubectl get pods -n gatekeeper-system
kubectl get crd | grep gatekeeper
```

Kiểm tra constraints:

```bash
kubectl get constrainttemplates
kubectl get k8sdisallowedimagetags
kubectl get k8srequiredlimits
kubectl get k8sdisallowrunasroot
kubectl get k8sdisallowhostnetwork
kubectl get k8smaxreplicas
```

## Test admission

Các manifest test nằm trong `gatekeeper/tests/`.

Manifest hợp lệ phải được API server nhận:

```bash
kubectl apply -f /opt/w10/gatekeeper/tests/good-deployment.yaml
kubectl delete -f /opt/w10/gatekeeper/tests/good-deployment.yaml
kubectl apply -f /opt/w10/gatekeeper/tests/good-replicas.yaml
kubectl delete -f /opt/w10/gatekeeper/tests/good-replicas.yaml
```

Các manifest vi phạm phải bị từ chối:

```bash
kubectl apply -f /opt/w10/gatekeeper/tests/bad-latest.yaml
kubectl apply -f /opt/w10/gatekeeper/tests/bad-no-limits.yaml
kubectl apply -f /opt/w10/gatekeeper/tests/bad-root.yaml
kubectl apply -f /opt/w10/gatekeeper/tests/bad-hostnetwork.yaml
kubectl apply -f /opt/w10/gatekeeper/tests/bad-replicas.yaml
```

Kỳ vọng:

- `bad-latest.yaml`: bị chặn vì dùng `nginx:latest`.
- `bad-no-limits.yaml`: bị chặn vì thiếu `resources.limits`.
- `bad-root.yaml`: bị chặn vì `runAsUser: 0`.
- `bad-hostnetwork.yaml`: bị chặn vì `hostNetwork: true`.
- `bad-replicas.yaml`: bị chặn vì `Deployment.spec.replicas` là `6`, lớn hơn `5`.

## Lưu ý với lab hiện tại

Constraint chỉ match namespace `demo` và các kind `Pod`, `Deployment`, `Rollout`
để không chặn controller hệ thống trong `kube-system`, `argocd`, `monitoring`,
`gatekeeper-system`.

Sau khi bật Gatekeeper, các pod test tạo bằng `kubectl run` trong namespace
`demo` cũng có thể bị chặn nếu dùng image `:latest` hoặc không khai báo limits.
Khi cần tạo pod test trong `demo`, dùng manifest có image pinned version và
`resources.limits`.
