# 07 - Payments Tenant Isolation

Challenge cuối thêm team `payments` vào platform đang có team cũ trong namespace
`demo`. Mục tiêu là cấp phòng riêng, giới hạn tài nguyên, cô lập network và kế
thừa guardrail cũ.

## File chính

```text
tenants/payments/
  namespace.yaml
  rbac.yaml
  quota-limitrange.yaml
  networkpolicy.yaml
  tests/

apps/payments/
  deployment.yaml
  service.yaml

argocd/apps/
  payments-tenant.yaml
  payments-app.yaml
```

`payments-tenant` sync hạ tầng tenant trước. `payments-app` sync workload sau.

## Namespace và guardrails

`tenants/payments/namespace.yaml` có label:

```yaml
guardrails.w10.dev/enforce: "true"
```

Gatekeeper constraints match label này. Vì vậy `payments` tự kế thừa các luật
cũ mà không cần viết constraint mới.

## RBAC least privilege

`payments-dev` được bind bằng `RoleBinding` trong namespace `payments`.

Điều này khác `ClusterRoleBinding`:

- `RoleBinding`: quyền chỉ trong namespace.
- `ClusterRoleBinding`: quyền toàn cluster.

Role không cấp quyền secrets hoặc rolebindings, nên payments-dev không đọc secret
và không tự nâng quyền.

Test:

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

## ResourceQuota và LimitRange

`ResourceQuota` giới hạn tổng tài nguyên namespace:

```yaml
requests.cpu: "1"
requests.memory: 1Gi
limits.cpu: "2"
limits.memory: 2Gi
pods: "10"
```

`LimitRange` cấp default request/limit cho container thiếu khai báo.

Vì sao cần cả hai:

- Quota chặn team dùng quá ngân sách.
- LimitRange tránh pod thiếu request/limit làm quota hoặc Gatekeeper khó kiểm soát.

Test quota:

```bash
kubectl apply -f /opt/w10/tenants/payments/tests/bad-quota-too-much-memory.yaml
```

Kỳ vọng bị reject.

Test default limit:

```bash
kubectl -n payments run defaulted-limits \
  --image=busybox:1.36.1 \
  --restart=Never \
  --command -- sleep 3600

kubectl -n payments get pod defaulted-limits \
  -o jsonpath='{.spec.containers[0].resources}'; echo

kubectl -n payments delete pod defaulted-limits --ignore-not-found
```

## NetworkPolicy

`networkpolicy.yaml` tạo:

- Default deny ingress.
- Allow ingress từ pod cùng namespace.
- Allow egress đến pod cùng namespace.
- Allow DNS egress đến kube-dns.

NetworkPolicy chỉ enforce nếu CNI hỗ trợ policy. Bootstrap mới dùng Calico:

```bash
kubectl get pods -n kube-system | grep calico
```

Test payments gọi demo bị chặn:

```bash
kubectl -n payments run curl-demo \
  --image=curlimages/curl:8.10.1 \
  --rm -i --restart=Never -- \
  curl -m 5 -sS http://api.demo.svc.cluster.local/healthz
```

Kỳ vọng timeout/fail nếu Calico đang enforce.

Test payments gọi service cùng namespace:

```bash
kubectl -n payments run curl-payments \
  --image=curlimages/curl:8.10.1 \
  --rm -i --restart=Never -- \
  curl -m 5 -sS http://payments-api.payments.svc.cluster.local/
```

Kỳ vọng thành công.

## Workload payments

`apps/payments/deployment.yaml` dùng image API và khai báo:

- tag không phải latest.
- `resources.requests` và `resources.limits`.
- `runAsUser: 1000`.
- replicas nhỏ.

Vì vậy workload hợp lệ với Gatekeeper.

Kiểm tra:

```bash
kubectl get deploy,svc,pod -n payments
```

## Test guardrail cũ chặn namespace mới

```bash
kubectl apply -f /opt/w10/tenants/payments/tests/bad-no-limits.yaml
```

Manifest thiếu limits phải bị Gatekeeper chặn. Đây là chứng minh quan trọng:
team mới kế thừa guardrail cũ bằng label namespace.

## ArgoCD ignore test manifests

`tenants/payments/.argocdignore` bỏ qua `tests/`, vì test manifests cố tình xấu.
Nếu ArgoCD apply cả tests, tenant app sẽ fail sync.
