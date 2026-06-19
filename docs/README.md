# W10 Lab Study Guide

Thư mục này là tài liệu học cho toàn bộ W10 lab. Mục tiêu không chỉ là chạy
được lệnh, mà hiểu vì sao từng thành phần tồn tại và khi lỗi thì nên nhìn vào
đâu.

## Nên đọc theo thứ tự

1. [00-overview.md](00-overview.md) - kiến trúc tổng thể và luồng hoạt động.
2. [01-terraform-ec2-bootstrap.md](01-terraform-ec2-bootstrap.md) - Terraform,
   EC2, Minikube, bootstrap và các output quan trọng.
3. [02-gitops-argocd.md](02-gitops-argocd.md) - App-of-Apps, sync, health,
   drift và cách debug ArgoCD.
4. [03-rollouts-monitoring-alerts.md](03-rollouts-monitoring-alerts.md) -
   Argo Rollouts, Prometheus, AnalysisTemplate, ServiceMonitor và Alertmanager.
5. [04-rbac-gatekeeper.md](04-rbac-gatekeeper.md) - RBAC và admission policy
   bằng OPA Gatekeeper.
6. [05-external-secrets-aws.md](05-external-secrets-aws.md) - AWS Secrets
   Manager, IAM, ESO và rotate secret.
7. [06-trivy-cosign-policy-controller.md](06-trivy-cosign-policy-controller.md)
   - Trivy scan, Cosign keyless signing và Sigstore admission verify.
8. [07-payments-tenant-isolation.md](07-payments-tenant-isolation.md) - thêm
   team `payments`, quota, LimitRange, NetworkPolicy và kế thừa guardrail.
9. [08-troubleshooting.md](08-troubleshooting.md) - lỗi thường gặp và hướng xử
   lý nhanh.

## Cách dùng tài liệu

- Các lệnh `terraform ...` chạy trên máy local, trong thư mục `terraform/ec2`.
- Các lệnh `kubectl ...` chạy trên EC2 sau khi SSH, trừ khi tài liệu ghi rõ là
  chạy trên máy local.
- ArgoCD Application nằm trong namespace `argocd`.
- Workload chính nằm trong namespace `demo`.
- Workload tenant mới nằm trong namespace `payments`.

## Các nguyên tắc cốt lõi của lab

- Git là desired state. ArgoCD đọc repo và đưa cluster về trạng thái đó.
- Controller tạo runtime state. Vì vậy một số resource có drift hợp lệ và cần
  `ignoreDifferences`.
- Admission policy nên opt-in bằng label namespace để áp cho nhiều team mà không
  phải copy luật.
- Secret thật không commit vào Git. Git chỉ chứa cách tham chiếu secret.
- Supply-chain policy chỉ nên enforce khi image đang chạy đã được ký đúng.
