# 00 - Tổng Quan Kiến Trúc

W10 lab mô phỏng một platform Kubernetes nhỏ nhưng đủ nhiều thành phần thực tế:
GitOps, progressive delivery, monitoring, admission policy, secret management,
supply-chain security và multi-tenant isolation.

## Luồng tổng thể

```text
Terraform
  -> EC2
  -> user_data bootstrap
  -> Docker + Minikube + kubectl + Helm + ArgoCD
  -> apply workload cơ bản
  -> người học apply argocd/root.yaml
  -> ArgoCD quản lý toàn bộ apps từ Git
```

Khi root app được apply:

```text
argocd/root.yaml
  -> argocd/apps/*
    -> common
    -> api
    -> analysis
    -> alert
    -> rbac
    -> gatekeeper
    -> gatekeeper-constraints
    -> external-secrets
    -> eso-config
    -> policy-controller
    -> policies
    -> payments-tenant
    -> payments-app
```

## Namespace chính

- `argocd`: ArgoCD server, repo server, application controller.
- `demo`: API chính, Argo Rollout, secret-reader, monitoring target.
- `monitoring`: Prometheus, Grafana, Alertmanager.
- `argo-rollouts`: Argo Rollouts controller.
- `gatekeeper-system`: Gatekeeper controller.
- `external-secrets`: External Secrets Operator và Kubernetes secret chứa AWS
  credentials cho ESO.
- `cosign-system`: Sigstore Policy Controller.
- `payments`: tenant/team thứ hai.

## Vì sao bootstrap vừa apply workload vừa có GitOps

Bootstrap EC2 apply workload cơ bản để lab có thể chạy ngay kể cả khi người học
chưa apply root app. Sau đó root app giúp ArgoCD quản lý repo theo GitOps.

Điểm cần nhớ:

- Bootstrap dùng image local `w10-api:local` để không phụ thuộc GHCR.
- ArgoCD sync từ Git có thể dùng image GHCR trong manifest.
- Nếu bật Cosign admission quá sớm, image local hoặc image chưa ký sẽ bị chặn.

## Các controller và trách nhiệm

| Controller | Trách nhiệm |
| --- | --- |
| ArgoCD | Sync desired state từ Git vào cluster |
| Argo Rollouts | Quản lý canary rollout và AnalysisRun |
| Prometheus Operator | Tạo Prometheus, Alertmanager, ServiceMonitor, PrometheusRule |
| Gatekeeper | Admission policy bằng ConstraintTemplate/Constraint |
| External Secrets Operator | Sync secret từ AWS Secrets Manager về Kubernetes Secret |
| Sigstore Policy Controller | Verify chữ ký Cosign ở admission |
| Kubernetes scheduler | Xếp pod lên node dựa trên request/resource |

## Lệnh kiểm tra sức khỏe tổng quát

```bash
kubectl get nodes
```

Kiểm tra node Minikube có `Ready` không.

```bash
kubectl get pods -A
```

Xem toàn bộ pod trong cluster. Đây là lệnh đầu tiên khi thấy UI hoặc app lỗi.

```bash
kubectl get applications -n argocd
```

Xem trạng thái GitOps. `Synced/Healthy` là trạng thái tốt; `OutOfSync`,
`Progressing`, `Degraded` cần đọc tiếp resource/events.

```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -50
```

Xem lỗi mới nhất trong cluster. Lệnh này thường chỉ ra nguyên nhân nhanh hơn UI.

## Khi học lab nên nhớ ba loại trạng thái

`Desired state`: YAML trong Git.

`Live state`: object thật trong Kubernetes.

`Runtime state`: field do controller thêm hoặc cập nhật, ví dụ status, webhook
CA bundle, default fields. Runtime state có thể làm ArgoCD báo OutOfSync nếu
không cấu hình ignore đúng.
