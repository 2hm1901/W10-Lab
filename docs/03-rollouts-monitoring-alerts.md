# 03 - Argo Rollouts, Monitoring Và Alerts

Phần này là lõi progressive delivery của lab: deploy API bằng Argo Rollouts,
quan sát metric bằng Prometheus và tự rollback nếu canary không đạt.

## API workload

Code nằm ở:

- `src/api/app.py`
- `src/api/Dockerfile`
- `app-api/rollout.yaml`
- `app-api/service.yaml`
- `app-api/servicemonitor.yaml`

`app.py` có 3 endpoint:

- `/`: trả JSON thành công hoặc lỗi giả lập.
- `/healthz`: health check cho Kubernetes probe.
- `/metrics`: metric Prometheus do `prometheus-flask-exporter` expose.

Biến môi trường:

```yaml
- name: VERSION
  value: "v0.0.1"
- name: ERROR_RATE
  value: "0"
```

`ERROR_RATE` là xác suất endpoint `/` trả HTTP 500. Đây là cách lab giả lập
canary lỗi.

## Rollout thay cho Deployment

`app-api/rollout.yaml` dùng:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
```

Rollout quản lý ReplicaSet giống Deployment nhưng có thêm strategy canary:

```yaml
strategy:
  canary:
    analysis:
      templates:
      - templateName: success-rate
      startingStep: 1
    steps:
    - setWeight: 10
    - pause: {duration: 2m}
    - setWeight: 50
    - pause: {duration: 2m}
    - setWeight: 100
```

Ý nghĩa:

- Đưa 10% traffic/pod sang version mới.
- Pause 2 phút.
- Chạy analysis từ Prometheus.
- Nếu đạt, tăng lên 50%, rồi 100%.
- Nếu fail, Rollout không promote tiếp.

## Vì sao replicas là 2

EC2 chạy nhiều controller nặng như Prometheus, ArgoCD, Gatekeeper, ESO, Policy
Controller. `replicas: 2` giúp lab phù hợp với tài nguyên hơn, tránh scheduler
báo `Insufficient cpu`.

## Service và ServiceMonitor

`app-api/service.yaml` tạo Service nội bộ cho API.

`app-api/servicemonitor.yaml` nói Prometheus Operator scrape service này.

ServiceMonitor cần label/selector khớp service. Nếu không có ServiceMonitor,
Prometheus không có metric để AnalysisTemplate query.

## AnalysisTemplate

`app-analysis/analysis-template.yaml` định nghĩa query Prometheus để tính success
rate.

Kiểm tra:

```bash
kubectl get analysistemplate -n demo
kubectl get analysisrun -n demo
```

`AnalysisRun` được Argo Rollouts tạo từ `AnalysisTemplate` trong lúc canary.

## PrometheusRule và Alertmanager

`app-alert/prometheus-rules.yaml` tạo alert rule dựa trên SLO/success rate.

Kiểm tra:

```bash
kubectl get prometheusrule -n monitoring
kubectl get servicemonitor -A
```

Alertmanager nhận alert từ Prometheus. Nếu cấu hình email, Alertmanager có thể
gửi Gmail app password qua secret `alertmanager-email`.

## Lệnh quan sát rollout

```bash
kubectl get rollout api -n demo
```

Xem Rollout object.

```bash
kubectl argo rollouts get rollout api -n demo
```

Xem tree rollout: ReplicaSet, pod, step hiện tại, analysis.

```bash
kubectl get pods -n demo -l app=api
```

Xem pod API đang chạy.

```bash
kubectl get rs -n demo
```

Xem ReplicaSet cũ/mới và số replica mong muốn.

## Restart Argo Rollout

`kubectl rollout restart` không hỗ trợ Argo Rollout CRD. Dùng:

```bash
kubectl argo rollouts restart api -n demo
```

Hoặc patch:

```bash
kubectl -n demo patch rollout api --type merge \
  -p "{\"spec\":{\"restartAt\":\"$(date -Iseconds)\"}}"
```

## Debug lỗi scheduling

```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -50
```

Nếu thấy:

```text
0/1 nodes are available: 1 Insufficient cpu
```

Nghĩa là tổng CPU request đã gần hết. Xem node:

```bash
kubectl describe node w10 | sed -n '/Allocated resources:/,/Events:/p'
```

Giải pháp:

- Giảm replicas.
- Scale workload phụ về 0 khi không test.
- Dùng `t3.xlarge` và `minikube_cpus=4`.

## Test API

Từ máy local:

```bash
cd terraform/ec2
curl "$(terraform output -raw api_url)"
curl "$(terraform output -raw api_url)/healthz"
curl "$(terraform output -raw api_url)/metrics"
```

Từ trong cluster:

```bash
kubectl -n monitoring run curl-api --image=curlimages/curl:8.10.1 --rm -i --restart=Never -- \
  curl -s http://api.demo.svc.cluster.local/healthz
```
