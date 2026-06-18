# Alert Test Guide

File này hướng dẫn chuẩn bị và test alert cho lab W10 trên EC2. Mục tiêu là
kiểm tra luồng:

```text
API /metrics -> ServiceMonitor -> PrometheusRule -> Alertmanager -> Email
```

## Trạng thái cần có trước khi test

Sau khi EC2 bootstrap xong, SSH vào EC2 rồi kiểm tra:

```bash
kubectl get pods -A
kubectl get rollout api -n demo
kubectl get servicemonitor -n demo
kubectl get prometheusrule -n monitoring
kubectl get pods -n monitoring
```

Kỳ vọng:

- Pod API trong namespace `demo` đang `Running`.
- `ServiceMonitor/api` tồn tại trong namespace `demo`.
- `PrometheusRule/slo-alerts` tồn tại trong namespace `monitoring`.
- Pod Prometheus và Alertmanager trong namespace `monitoring` đang chạy.

Nếu ArgoCD UI đã có app nhưng alert resources chưa có, sync app `alert` hoặc
apply lại bằng tay:

```bash
kubectl apply -f /opt/w10/app-alert/prometheus-rules.yaml
```

## 1. Chuẩn bị Gmail App Password

Alertmanager đang cấu hình gửi email qua Gmail SMTP trong
`argocd/apps/k8s-prometheus.yaml`.

Bạn cần tạo Gmail App Password:

```text
https://myaccount.google.com/apppasswords
```

Copy password 16 ký tự. Đây không phải password đăng nhập Gmail thường.

Lưu ý: file secret chứa password không được commit lên Git.

## 2. Tạo email secret trên EC2

Trong EC2:

```bash
cd /opt/w10
cp app-alert/email-secret.yaml.example app-alert/email-secret.yaml
nano app-alert/email-secret.yaml
```

Sửa:

```yaml
stringData:
  password: your-gmail-app-password-16-chars
```

Apply secret:

```bash
kubectl apply -f app-alert/email-secret.yaml
```

Kiểm tra secret đã có:

```bash
kubectl get secret alertmanager-email -n monitoring
```

## 3. Đảm bảo Alertmanager đọc được secret

Chart `kube-prometheus-stack` mount secret `alertmanager-email` vào
Alertmanager. Nếu secret được tạo sau khi Alertmanager đã chạy, restart
Alertmanager để chắc chắn pod mount secret mới:

```bash
kubectl get statefulset -n monitoring | grep alertmanager
kubectl rollout restart statefulset alertmanager-kube-prometheus-stack-alertmanager -n monitoring
kubectl rollout status statefulset alertmanager-kube-prometheus-stack-alertmanager -n monitoring --timeout=5m
```

Nếu tên StatefulSet khác, thay
`alertmanager-kube-prometheus-stack-alertmanager` bằng tên bạn thấy từ lệnh
`kubectl get statefulset -n monitoring`.

Kiểm tra file password đã được mount:

```bash
kubectl exec -n monitoring -c alertmanager \
  $(kubectl get pod -n monitoring -l app.kubernetes.io/name=alertmanager -o name | head -1) \
  -- ls /etc/alertmanager/secrets/alertmanager-email/
```

Kỳ vọng output có file:

```text
password
```

## 4. Kiểm tra Prometheus đã scrape API

Tạo một ít traffic để API có metric:

```bash
for i in $(seq 1 100); do
  kubectl -n monitoring run curl-api-$i --image=curlimages/curl:8.10.1 --rm -i --restart=Never -- \
    curl -s http://api.demo.svc.cluster.local/ >/dev/null || true
done
```

Query Prometheus success rate:

```bash
kubectl run prom-query --image=curlimages/curl:8.10.1 --rm -i --restart=Never -n monitoring -- \
  curl -s 'http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query?query=api:success_rate:5m'
```

Nếu chưa có data, đợi 1-2 phút rồi query lại. ServiceMonitor scrape mỗi 15 giây,
PrometheusRule evaluate mỗi 30 giây.

## 5. Trigger SLO alert trên EC2

Để alert `SLOViolation` fire, success rate phải thấp hơn `95%` trong ít nhất
`2m`, theo rule:

```yaml
expr: api:success_rate:5m < 0.95
for: 2m
```

Patch Rollout trên EC2 để tăng lỗi lên 20%:

```bash
kubectl -n demo patch rollout api --type='json' \
  -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/env/1/value","value":"0.20"},
    {"op":"replace","path":"/spec/template/spec/containers/0/env/0/value","value":"alert-test"}
  ]'
```

Theo dõi rollout:

```bash
kubectl argo rollouts get rollout api -n demo --watch
```

Tạo traffic liên tục trong 3-5 phút để metric đủ dữ liệu:

```bash
while true; do
  kubectl -n monitoring run curl-api-$(date +%s%N) --image=curlimages/curl:8.10.1 --rm -i --restart=Never -- \
    curl -s http://api.demo.svc.cluster.local/ >/dev/null || true
  sleep 1
done
```

Dừng bằng `Ctrl+C` sau vài phút.

## 6. Quan sát alert

Kiểm tra PrometheusRule:

```bash
kubectl get prometheusrule slo-alerts -n monitoring
```

Query alert trong Prometheus:

```bash
kubectl run prom-alert-query --image=curlimages/curl:8.10.1 --rm -i --restart=Never -n monitoring -- \
  curl -s 'http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query?query=ALERTS%7Balertname%3D%22SLOViolation%22%7D'
```

Mở Alertmanager từ máy local:

```bash
cd terraform/ec2
terraform output -raw alertmanager_url
```

Hoặc xem ngay trong EC2:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

Nếu email config đúng, bạn sẽ nhận email sau khi alert firing và route tới
receiver `email-notifications`.

## 7. Reset sau khi test

Đưa lỗi về 0:

```bash
kubectl -n demo patch rollout api --type='json' \
  -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/env/1/value","value":"0"},
    {"op":"replace","path":"/spec/template/spec/containers/0/env/0/value","value":"reset"}
  ]'
```

Theo dõi rollout trở lại ổn định:

```bash
kubectl argo rollouts get rollout api -n demo --watch
```

Alert sẽ tự chuyển sang resolved sau khi success rate hồi phục và Prometheus
evaluate lại rule.

## Files

- `email-secret.yaml.example`: mẫu secret Gmail App Password.
- `email-secret.yaml`: file secret thật, không commit.
- `prometheus-rules.yaml`: rule ghi `api:success_rate:5m` và alert
  `SLOViolation`.
- `argocd/apps/k8s-prometheus.yaml`: Helm values cấu hình Alertmanager receiver.
