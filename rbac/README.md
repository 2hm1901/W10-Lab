# RBAC Guide

RBAC này tạo 3 vai trò theo yêu cầu lab:

| User | Vai trò | Được làm gì |
| --- | --- | --- |
| `alice` | `developer` | CRUD workload trong namespace `demo` |
| `bob` | `sre` | Xem và thao tác pod toàn cụm |
| `carol` | `viewer` | Chỉ đọc toàn cụm: `get/list/watch` |

## Deploy qua GitOps

Nếu đã apply App-of-Apps root:

```bash
kubectl apply -f /opt/w10/argocd/root.yaml
```

ArgoCD sẽ tạo app `rbac` từ `argocd/apps/rbac.yaml`.

Nếu muốn apply thủ công trên EC2:

```bash
kubectl apply -f /opt/w10/rbac/
```

## Test phân quyền

Chạy trên EC2:

```bash
kubectl auth can-i create deployments -n demo --as=alice
kubectl auth can-i create deployments -n default --as=alice
kubectl auth can-i delete pods -A --as=bob
kubectl auth can-i get pods -A --as=carol
kubectl auth can-i delete pods -A --as=carol
```

Kỳ vọng:

```text
yes
no
yes
yes
no
```

## Ghi chú

- `alice` dùng `Role` + `RoleBinding` trong namespace `demo`, nên không có quyền
  ở namespace khác.
- `bob` dùng `ClusterRole` + `ClusterRoleBinding`, nên quyền áp dụng toàn cụm.
- `carol` dùng `ClusterRole` chỉ có `get/list/watch`, không có `create/update/delete`.
- Các subject là `kind: User`; lab kiểm tra bằng `kubectl auth can-i --as=<user>`.
