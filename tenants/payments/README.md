# Payments Tenant Challenge

Mục tiêu: thêm team `payments` vào platform nhưng vẫn cô lập an toàn với team
cũ trong namespace `demo`.

## Kiến trúc

```text
tenants/payments/
  namespace.yaml          # namespace + labels opt-in guardrails
  rbac.yaml               # Role + RoleBinding cho payments-dev
  quota-limitrange.yaml   # ResourceQuota + LimitRange
  networkpolicy.yaml      # deny mặc định, chỉ cho cùng namespace + DNS

apps/payments/
  deployment.yaml         # workload hợp lệ của team payments
  service.yaml

argocd/apps/
  payments-tenant.yaml    # sync hạ tầng tenant trước
  payments-app.yaml       # sync workload sau
```

## Vì sao guardrail cũ tự áp cho payments

Gatekeeper constraints không còn hard-code namespace `demo`. Chúng match namespace
có label:

```yaml
guardrails.w10.dev/enforce: "true"
```

Cả `demo` và `payments` đều có label này, nên các luật cũ như cấm `:latest`, bắt
buộc `resources.limits`, cấm `runAsUser: 0`, cấm `hostNetwork` và cấm replicas
`> 5` tự áp cho namespace mới mà không cần viết constraint riêng.

Sigstore Policy Controller cũng dùng opt-in label:

```yaml
policy.sigstore.dev/include: "true"
```

Vì vậy workload trong `payments` cũng đi qua admission verify image giống team
cũ. App mẫu dùng `ghcr.io/2hm1901/w10-api:0.0.1`, là image được workflow
Trivy/Cosign scan và ký trong Lab 2.2.

## Vì sao Role/RoleBinding giữ cô lập

`payments-dev` chỉ được bind bằng `RoleBinding` trong namespace `payments`.
Không dùng `ClusterRoleBinding`, nên quyền không lan sang `demo` hoặc namespace
khác. Role cũng không cấp quyền `secrets` và không cấp quyền sửa
`roles/rolebindings`.

## Sync bằng ArgoCD

Sau khi root app refresh, kiểm tra:

```bash
kubectl get application payments-tenant payments-app -n argocd
kubectl get ns payments --show-labels
kubectl get role,rolebinding -n payments
kubectl get resourcequota,limitrange -n payments
kubectl get networkpolicy -n payments
kubectl get deploy,svc,pod -n payments
```

Nếu app mới chưa xuất hiện:

```bash
kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
```

## Chứng minh 1 - RBAC least privilege

```bash
kubectl auth can-i create deployments -n payments --as=payments-dev
kubectl auth can-i create deployments -n demo --as=payments-dev
kubectl auth can-i get secrets -n payments --as=payments-dev
kubectl auth can-i update rolebindings -n payments --as=payments-dev
```

Kỳ vọng:

```text
yes
no
no
no
```

## Chứng minh 2 - Quota và LimitRange

Pod vượt budget phải bị từ chối:

```bash
kubectl apply -f /opt/w10/tenants/payments/tests/bad-quota-too-much-memory.yaml
```

Pod thiếu limits vẫn được LimitRange cấp default nếu tạo trực tiếp:

```bash
kubectl -n payments run defaulted-limits \
  --image=busybox:1.36.1 \
  --restart=Never \
  --command -- sleep 3600

kubectl -n payments get pod defaulted-limits \
  -o jsonpath='{.spec.containers[0].resources}'; echo

kubectl -n payments delete pod defaulted-limits --ignore-not-found
```

## Chứng minh 3 - NetworkPolicy cô lập

NetworkPolicy chỉ enforce nếu cluster dùng CNI hỗ trợ policy, ví dụ Calico. Với
Terraform/bootstrap mới, Minikube được tạo bằng `--cni=calico`.

Payments gọi service trong `demo` phải timeout/fail:

```bash
kubectl -n payments run curl-demo \
  --image=curlimages/curl:8.10.1 \
  --rm -i --restart=Never -- \
  curl -m 5 -sS http://api.demo.svc.cluster.local/healthz
```

Payments gọi service cùng namespace phải được:

```bash
kubectl -n payments run curl-payments \
  --image=curlimages/curl:8.10.1 \
  --rm -i --restart=Never -- \
  curl -m 5 -sS http://payments-api.payments.svc.cluster.local/
```

## Chứng minh 4 - App hợp lệ chạy, vi phạm bị constraint cũ chặn

App hợp lệ qua GitOps:

```bash
kubectl get deploy payments-api -n payments
kubectl get pods -n payments -l app=payments-api
```

Manifest thiếu limits trong `payments` phải bị Gatekeeper chặn:

```bash
kubectl apply -f /opt/w10/tenants/payments/tests/bad-no-limits.yaml
```

Kết quả mong muốn là API server reject với message liên quan đến
`resources.limits`.
