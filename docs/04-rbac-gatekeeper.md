# 04 - RBAC Và OPA Gatekeeper

Phần này tập trung vào kiểm soát quyền và admission policy.

## RBAC: ai được làm gì

Manifest nằm ở:

- `rbac/roles.yaml`
- `rbac/rolebindings.yaml`

Lab tạo 3 user giả lập:

| User | Vai trò | Quyền |
| --- | --- | --- |
| `alice` | developer | CRUD workload trong namespace `demo` |
| `bob` | sre | Xem/thao tác pod toàn cluster |
| `carol` | viewer | Chỉ đọc toàn cluster |

Các user này không cần tồn tại như Kubernetes object. `kubectl auth can-i
--as=<user>` giả lập request dưới username đó để RBAC evaluate.

## Role và ClusterRole

`Role` chỉ có hiệu lực trong một namespace:

```yaml
kind: Role
metadata:
  namespace: demo
```

`ClusterRole` có scope toàn cluster, nhưng chỉ có quyền thật khi được bind.

`RoleBinding` bind quyền trong namespace. `ClusterRoleBinding` bind quyền toàn
cluster.

## Test RBAC

```bash
kubectl auth can-i create deployments -n demo --as=alice
```

Alice tạo deployment trong `demo`: kỳ vọng `yes`.

```bash
kubectl auth can-i create deployments -n default --as=alice
```

Alice không có quyền ngoài `demo`: kỳ vọng `no`.

```bash
kubectl auth can-i delete pods -A --as=bob
```

Bob là SRE có quyền thao tác pod toàn cluster: kỳ vọng `yes`.

```bash
kubectl auth can-i delete pods -A --as=carol
```

Carol chỉ đọc: kỳ vọng `no`.

## Gatekeeper: admission policy

Manifest nằm ở:

- `gatekeeper/constraints/templates.yaml`
- `gatekeeper/constraints/constraints.yaml`
- `gatekeeper/tests/*`

Gatekeeper dùng 2 lớp:

`ConstraintTemplate`: định nghĩa loại policy và Rego logic.

`Constraint`: instance cụ thể của policy, chọn namespace/kind và parameters.

## Các luật đang enforce

| Constraint | Ý nghĩa |
| --- | --- |
| `K8sDisallowedImageTags` | Cấm image tag `:latest` |
| `K8sRequiredLimits` | Bắt buộc container có `resources.limits` |
| `K8sDisallowRunAsRoot` | Cấm `runAsUser: 0` |
| `K8sDisallowHostNetwork` | Cấm `hostNetwork: true` |
| `K8sMaxReplicas` | Cấm Deployment replicas lớn hơn 5 |

## Vì sao match bằng namespace label

Constraints match namespace có label:

```yaml
guardrails.w10.dev/enforce: "true"
```

Lợi ích:

- Không hard-code mỗi namespace.
- Team mới chỉ cần label namespace là kế thừa guardrail.
- Không cần copy constraint cho `payments`.

## Kiểm tra Gatekeeper

```bash
kubectl get pods -n gatekeeper-system
```

Gatekeeper controller phải Running.

```bash
kubectl get constrainttemplates
```

Xem các template policy.

```bash
kubectl get k8sdisallowedimagetags,k8srequiredlimits,k8sdisallowrunasroot,k8sdisallowhostnetwork,k8smaxreplicas
```

Xem constraint instances.

## Test manifest hợp lệ

```bash
kubectl apply -f /opt/w10/gatekeeper/tests/good-deployment.yaml
kubectl delete -f /opt/w10/gatekeeper/tests/good-deployment.yaml
```

Manifest hợp lệ phải apply được.

## Test manifest vi phạm

```bash
kubectl apply -f /opt/w10/gatekeeper/tests/bad-latest.yaml
kubectl apply -f /opt/w10/gatekeeper/tests/bad-no-limits.yaml
kubectl apply -f /opt/w10/gatekeeper/tests/bad-root.yaml
kubectl apply -f /opt/w10/gatekeeper/tests/bad-hostnetwork.yaml
kubectl apply -f /opt/w10/gatekeeper/tests/bad-replicas.yaml
```

Các lệnh này phải bị API server từ chối. Đây là admission-time rejection, nghĩa
là object xấu không được tạo.

## Debug Gatekeeper

```bash
kubectl describe k8srequiredlimits require-cpu-memory-limits
```

Xem constraint match gì, parameter gì, có violation audit không.

```bash
kubectl logs -n gatekeeper-system deploy/gatekeeper-controller-manager --tail=100
```

Xem log controller khi policy có vấn đề.
