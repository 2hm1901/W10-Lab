# W10 Lab - Progressive Delivery on Kubernetes

Lab này demo GitOps progressive delivery cho Flask API bằng Kubernetes, ArgoCD,
Argo Rollouts, Prometheus và AlertManager. Ban đầu lab chạy local bằng Minikube;
repo hiện đã có thêm Terraform để dựng một EC2 trên AWS và bootstrap toàn bộ lab
ngay trên EC2.

## Mục tiêu lab

- Deploy API bằng `Rollout` thay vì `Deployment`.
- Canary theo các bước `10% -> 50% -> 100%`.
- Dùng `AnalysisTemplate` query Prometheus để kiểm tra success rate.
- Tự rollback nếu canary không đạt điều kiện.
- Dùng `PrometheusRule` và AlertManager để cảnh báo khi SLO bị vi phạm.
- Chạy được ở 2 môi trường:
  - Local: Minikube trên máy cá nhân.
  - AWS: Minikube single-node trên EC2, tạo bằng Terraform.

## Thành phần chính

- `src/api`: Flask API có endpoint `/`, `/healthz`, `/metrics`.
- `app-api`: Argo Rollout, Service và ServiceMonitor cho API.
- `app-analysis`: AnalysisTemplate dùng Prometheus để chấm canary.
- `app-alert`: PrometheusRule và mẫu secret email cho AlertManager.
- `app-common`: Namespace dùng chung cho workload demo.
- `argocd`: App-of-Apps và các ArgoCD Application.
- `rbac`: Role, ClusterRole và binding cho user `alice`, `bob`, `carol`.
- `gatekeeper`: OPA Gatekeeper constraints chặn manifest vi phạm admission.
- `terraform/ec2`: Terraform tạo EC2, SSH key pair, security group và bootstrap lab.

## Cấu trúc repo

```text
W10/
├── app-api/
│   ├── rollout.yaml
│   ├── service.yaml
│   └── servicemonitor.yaml
├── app-analysis/
│   └── analysis-template.yaml
├── app-alert/
│   ├── prometheus-rules.yaml
│   ├── email-secret.yaml.example
│   └── README.md
├── app-common/
│   └── demo-namespace.yaml
├── argocd/
│   ├── apps/
│   └── root.yaml
├── rbac/
│   ├── roles.yaml
│   ├── rolebindings.yaml
│   └── README.md
├── gatekeeper/
│   ├── constraints/
│   ├── tests/
│   └── README.md
├── src/api/
│   ├── app.py
│   └── Dockerfile
└── terraform/ec2/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── user_data.sh.tftpl
    └── README.md
```

## Chạy trên AWS EC2

Terraform trong `terraform/ec2` tạo:

- EC2 Amazon Linux 2023, mặc định `t3.large`, root disk `50GiB`.
- Security Group mở SSH và các port lab.
- SSH key pair bằng provider `tls` và lưu private key bằng provider `local`.
- Docker, Minikube, kubectl, Helm, ArgoCD CLI, kubectl argo rollouts plugin.
- ArgoCD, Argo Rollouts, kube-prometheus-stack, API workload và rule cảnh báo.
- Port-forward systemd services để truy cập lab từ public IP của EC2.

### Deploy EC2

```bash
cd terraform/ec2
cp terraform.tfvars.example terraform.tfvars
```

Sửa `terraform.tfvars`:

```hcl
ssh_allowed_cidr = "YOUR_PUBLIC_IP/32"
lab_allowed_cidr = "YOUR_PUBLIC_IP/32"
```

Apply:

```bash
terraform init
terraform plan
terraform apply
```

Sau khi `terraform apply` xong, Terraform mới chỉ đảm bảo EC2 đã được tạo. Bên
trong EC2, `user_data` vẫn đang chạy bootstrap để cài tool và deploy lab. Vì vậy
việc tiếp theo là SSH vào EC2 và theo dõi log bootstrap.

Trên máy local:

```bash
ssh -i generated/w10.pem ec2-user@$(terraform output -raw public_ip)
```

Trong EC2:

```bash
sudo tail -f /var/log/w10-bootstrap.log
```

Bootstrap thành công khi log chạy qua các bước chính sau:

- Minikube báo `Done! kubectl is now configured to use "w10" cluster`.
- Docker build image `w10-api:local` thành công.
- `minikube image load w10-api:local` nạp image vào cluster.
- ArgoCD deployment rollout xong.
- Helm cài xong `argo-rollouts` và `kube-prometheus-stack`.
- Các manifest trong `app-common`, `app-analysis`, `app-alert`, `app-api` được apply.
- File `/home/ec2-user/w10-lab-info.txt` được tạo.

Nếu log dừng giữa chừng, chưa nên test rollout hoặc UI vội. Hãy đọc 50-100 dòng
cuối log để xem lỗi cụ thể:

```bash
sudo tail -n 100 /var/log/w10-bootstrap.log
```

### Sau khi bootstrap xong

Mục tiêu của các bước dưới đây là xác nhận từng lớp của lab đã hoạt động:
Kubernetes trước, sau đó controller/monitoring, sau đó API và cuối cùng là UI.

#### 1. Kiểm tra Kubernetes cluster

```bash
kubectl get nodes
kubectl get ns
kubectl get pods -A
```

Vì sao làm bước này: nếu node hoặc pod hệ thống chưa ổn, các lỗi ở ArgoCD,
Rollouts hoặc Prometheus phía sau chỉ là hệ quả. Cluster ổn thì node `w10`
phải `Ready`, các pod `kube-system` phải `Running`.

#### 2. Kiểm tra controller và CRD của lab

```bash
kubectl get crd | grep -E 'argoproj.io|monitoring.coreos.com'
kubectl get pods -n argocd
kubectl get pods -n argo-rollouts
kubectl get pods -n monitoring
```

Vì sao làm bước này: `Rollout`, `AnalysisRun`, `ServiceMonitor` và
`PrometheusRule` là custom resources. Nếu CRD chưa có, các lệnh như
`kubectl get rollout` hoặc `kubectl get servicemonitor` sẽ báo
`the server doesn't have a resource type`.

#### 3. Kiểm tra API rollout

```bash
kubectl get rollout api -n demo
kubectl argo rollouts get rollout api -n demo
kubectl get analysisrun -n demo
kubectl get servicemonitor,prometheusrule -A
```

Vì sao làm bước này: đây là phần chính của lab. `Rollout` cho biết canary đang
ở bước nào, `AnalysisRun` cho biết Prometheus query có pass hay fail, còn
`ServiceMonitor`/`PrometheusRule` xác nhận monitoring đã nhận workload.

#### 4. Tạo ArgoCD apps thủ công

Bootstrap trên EC2 cài ArgoCD và deploy workload chính bằng `kubectl apply` để
lab chạy được ngay, nhưng không tự apply `argocd/root.yaml`. Vì vậy khi mở
ArgoCD UI lần đầu, bạn có thể thấy chưa có app nào. Đây là bình thường.

Nếu muốn ArgoCD quản lý repo theo mô hình App-of-Apps, chạy lệnh này trong EC2:

```bash
kubectl apply -f /opt/w10/argocd/root.yaml
```

Sau đó kiểm tra:

```bash
kubectl get applications -n argocd
```

Vì sao làm bước này: `argocd/root.yaml` tạo root Application. Root app này trỏ
tới thư mục `argocd/apps`, sau đó ArgoCD sẽ tạo các child apps như `api`,
`analysis`, `alert`, `common`, `rbac`, `gatekeeper`, `gatekeeper-constraints`,
`argo-rollouts` và `kube-prometheus-stack`.
Nếu chưa apply root app thì ArgoCD UI chỉ có server rỗng, không có Application.

Lưu ý: EC2 bootstrap đã patch và apply bản manifest local để dùng image
`w10-api:local`. Còn ArgoCD sync từ Git repo sẽ đọc manifest trong repo, thường
dùng image GHCR như `ghcr.io/2hm1901/w10-api:<tag>`. Nếu GHCR image/package
private hoặc chưa pull được, app `api` trong ArgoCD có thể báo sync/deploy lỗi
dù workload local bootstrap đã chạy.

#### 5. Test API

Trên máy local, lấy URL API:

```bash
cd terraform/ec2
terraform output -raw api_url
```

Gọi thử API:

```bash
curl "$(terraform output -raw api_url)"
curl "$(terraform output -raw api_url)/healthz"
curl "$(terraform output -raw api_url)/metrics"
```

Vì sao làm bước này:

- `/` xác nhận app trả response nghiệp vụ.
- `/healthz` là endpoint Kubernetes dùng cho liveness/readiness probe.
- `/metrics` là endpoint Prometheus scrape để tính success rate.

Nếu đang SSH trong EC2 thì không dùng được `terraform output` trừ khi bạn cũng
copy Terraform state vào EC2. Khi ở trong EC2, gọi qua service nội bộ:

```bash
kubectl -n monitoring run curl-api --image=curlimages/curl:8.10.1 --rm -i --restart=Never -- \
  curl -s http://api.demo.svc.cluster.local/healthz
```

#### 6. Truy cập các UI và endpoint public

Trên máy local:

```bash
terraform output argocd_url
terraform output api_url
terraform output prometheus_url
terraform output grafana_url
terraform output alertmanager_url
```

Port mặc định:

- ArgoCD: `8080`
- API: `8081`
- Prometheus: `9090`
- Grafana: `3000`
- Alertmanager: `9093`

Vì sao làm bước này:

- ArgoCD để xem trạng thái sync GitOps và các Application.
- API để test workload từ bên ngoài EC2.
- Prometheus để query metric, ví dụ success rate.
- Grafana để xem dashboard do kube-prometheus-stack tạo.
- Alertmanager để xem alert firing/resolved.

Lấy password ArgoCD:

```bash
terraform output -raw argocd_initial_password_command
```

Copy command được in ra và chạy. User mặc định của ArgoCD là `admin`. Trình
duyệt có thể cảnh báo HTTPS certificate vì ArgoCD dùng self-signed cert trong
lab; accept để tiếp tục.

#### 7. Đọc file hướng dẫn nhanh trên EC2

Bootstrap tạo sẵn file này trong EC2:

```bash
cat /home/ec2-user/w10-lab-info.txt
```

File này nhắc lại các lệnh kiểm tra thường dùng và danh sách port đang expose.

## Test RBAC

RBAC lab tạo 3 user giả lập để kiểm tra bằng `kubectl auth can-i --as=<user>`:

| User | Vai trò | Quyền |
| --- | --- | --- |
| `alice` | developer | CRUD workload trong namespace `demo` |
| `bob` | sre | Xem và thao tác pod toàn cụm |
| `carol` | viewer | Chỉ đọc toàn cụm |

Nếu đã apply root app, ArgoCD sẽ sync app `rbac`. Kiểm tra:

```bash
kubectl get application rbac -n argocd
kubectl get role,rolebinding -n demo
kubectl get clusterrole,clusterrolebinding | grep -E 'sre|viewer|rbac-self-check|bob|carol'
```

Nếu muốn apply thủ công trên EC2:

```bash
kubectl apply -f /opt/w10/rbac/
```

Test phân quyền:

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

Chi tiết nằm trong `rbac/README.md`.

## Test Gatekeeper

Gatekeeper lab enforce 4 luật trong namespace `demo`:

| Luật | Ý nghĩa |
| --- | --- |
| Cấm `:latest` | Image phải pin version |
| Bắt buộc `resources.limits` | Container phải có CPU/memory limit |
| Cấm `runAsUser: 0` | Không chạy container bằng root user |
| Cấm `hostNetwork: true` | Không dùng host network |

Nếu đã apply root app, ArgoCD sẽ sync 2 app:

```bash
kubectl get application gatekeeper -n argocd
kubectl get application gatekeeper-constraints -n argocd
```

Kiểm tra controller và constraints:

```bash
kubectl get pods -n gatekeeper-system
kubectl get constrainttemplates
kubectl get k8sdisallowedimagetags,k8srequiredlimits,k8sdisallowrunasroot,k8sdisallowhostnetwork
```

Test manifest hợp lệ:

```bash
kubectl apply -f /opt/w10/gatekeeper/tests/good-deployment.yaml
kubectl delete -f /opt/w10/gatekeeper/tests/good-deployment.yaml
```

Test manifest xấu, các lệnh dưới đây phải bị API server từ chối:

```bash
kubectl apply -f /opt/w10/gatekeeper/tests/bad-latest.yaml
kubectl apply -f /opt/w10/gatekeeper/tests/bad-no-limits.yaml
kubectl apply -f /opt/w10/gatekeeper/tests/bad-root.yaml
kubectl apply -f /opt/w10/gatekeeper/tests/bad-hostnetwork.yaml
```

Chi tiết nằm trong `gatekeeper/README.md`.

## Chạy local bằng Minikube

### 1. Tạo cluster

```bash
minikube start -p w10 --driver=docker
kubectl config use-context w10
```

### 2. Cài ArgoCD

```bash
kubectl create ns argocd
kubectl apply --server-side -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server
```

### 3. Truy cập ArgoCD

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### 4. Build image API

Với local Minikube, cách đơn giản là build image trên máy local rồi load vào
Minikube:

```bash
docker build -t w10-api:local src/api
minikube -p w10 image load w10-api:local
```

Sau đó sửa `app-api/rollout.yaml`:

```yaml
image: w10-api:local
imagePullPolicy: Never
```

Nếu dùng GitHub Actions/GHCR, workflow `.github/workflows/build-push.yml` sẽ build
image `ghcr.io/<owner>/w10-api:<tag>` và cập nhật `app-api/rollout.yaml`.

### 5. Deploy App-of-Apps

```bash
kubectl apply -f argocd/root.yaml
```

## Test scenarios

Các test dưới đây dùng để chứng minh vòng feedback của progressive delivery:
bạn thay error rate, GitOps/ArgoCD sync manifest mới, Argo Rollouts tạo canary,
AnalysisTemplate hỏi Prometheus, rồi rollout pass hoặc rollback dựa trên metric.

### Chuẩn bị trước khi test trên EC2

SSH vào EC2:

```bash
ssh -i terraform/ec2/generated/w10.pem ec2-user@$(cd terraform/ec2 && terraform output -raw public_ip)
```

Kiểm tra các thành phần chính:

```bash
kubectl get applications -n argocd
kubectl get pods -A
kubectl get rollout api -n demo
kubectl get analysisrun -n demo
kubectl get servicemonitor -n demo
kubectl get prometheusrule -n monitoring
```

Kỳ vọng:

- ArgoCD đã có root app và các child apps nếu bạn đã chạy
  `kubectl apply -f /opt/w10/argocd/root.yaml`.
- API rollout tồn tại trong namespace `demo`.
- Prometheus stack chạy trong namespace `monitoring`.
- `ServiceMonitor/api` và `PrometheusRule/slo-alerts` tồn tại.

Mở 2 terminal SSH vào EC2 sẽ dễ quan sát hơn:

Terminal 1, watch rollout:

```bash
kubectl argo rollouts get rollout api -n demo --watch
```

Terminal 2, xem AnalysisRun và event:

```bash
watch -n 5 'kubectl get analysisrun -n demo; echo; kubectl get events -n demo --sort-by=.lastTimestamp | tail -20'
```

Tạo traffic trong lúc test để Prometheus có metric:

```bash
while true; do
  kubectl -n monitoring run curl-api-$(date +%s%N) --image=curlimages/curl:8.10.1 --rm -i --restart=Never -- \
    curl -s http://api.demo.svc.cluster.local/ >/dev/null || true
  sleep 1
done
```

Dừng traffic bằng `Ctrl+C` sau khi test xong.

### Cách thay đổi workload khi test

Có 2 cách:

- GitOps: sửa `app-api/rollout.yaml`, commit, push, để ArgoCD sync.
- EC2 nhanh: patch trực tiếp `Rollout` bằng `kubectl patch`.

Với lab trên EC2, cách patch trực tiếp dễ quan sát hơn vì không phụ thuộc GHCR
image pull. Khi patch, luôn đổi cả `VERSION` để Kubernetes tạo ReplicaSet mới.

### Test 1: Canary thành công

Mục tiêu: chứng minh version mới có success rate tốt thì rollout được promote.

Chạy trên EC2:

```bash
kubectl -n demo patch rollout api --type='json' \
  -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/env/0/value","value":"success-test"},
    {"op":"replace","path":"/spec/template/spec/containers/0/env/1/value","value":"0"}
  ]'
```

Theo dõi:

```bash
kubectl argo rollouts get rollout api -n demo --watch
kubectl get analysisrun -n demo
```

Kiểm tra API:

```bash
kubectl -n monitoring run curl-success --image=curlimages/curl:8.10.1 --rm -i --restart=Never -- \
  curl -s http://api.demo.svc.cluster.local/
```

Kỳ vọng:

- Rollout đi qua các bước `10% -> 50% -> 100%`.
- AnalysisRun `Successful`.
- Rollout cuối cùng `Healthy`.

### Test 2: Canary fail và rollback

Mục tiêu: chứng minh version mới có lỗi cao thì AnalysisRun fail và rollout
không promote version lỗi.

Patch `ERROR_RATE` cao để fail rõ ràng. Dùng `0.50` thay vì `0.15` để kết quả
ổn định hơn khi canary chỉ nhận một phần traffic.

```bash
kubectl -n demo patch rollout api --type='json' \
  -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/env/0/value","value":"fail-test"},
    {"op":"replace","path":"/spec/template/spec/containers/0/env/1/value","value":"0.50"}
  ]'
```

Theo dõi:

```bash
kubectl argo rollouts get rollout api -n demo --watch
kubectl get analysisrun -n demo
kubectl describe analysisrun -n demo $(kubectl get analysisrun -n demo --sort-by=.metadata.creationTimestamp -o name | tail -1)
```

Kỳ vọng:

- AnalysisRun fail vì query Prometheus thấy success rate thấp hơn `0.90`.
- Rollout không promote bản `fail-test` lên stable.
- Argo Rollouts giữ hoặc rollback về ReplicaSet ổn định trước đó.

Nếu AnalysisRun chưa fail ngay, tiếp tục tạo traffic thêm vài phút. Prometheus
cần đủ mẫu trong cửa sổ `[2m]` của `app-analysis/analysis-template.yaml`.

### Test 3: Trigger SLO alert

Mục tiêu: chứng minh alert SLO dùng ngưỡng khác với canary analysis.

- Canary analysis pass nếu success rate `>= 90%`.
- SLO alert fire nếu success rate `< 95%` trong `2m`.

Patch lỗi khoảng 10-20%. `0.20` dễ thấy alert hơn:

```bash
kubectl -n demo patch rollout api --type='json' \
  -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/env/0/value","value":"slo-alert-test"},
    {"op":"replace","path":"/spec/template/spec/containers/0/env/1/value","value":"0.20"}
  ]'
```

Tạo traffic liên tục 3-5 phút, rồi query Prometheus:

```bash
kubectl run prom-success-query --image=curlimages/curl:8.10.1 --rm -i --restart=Never -n monitoring -- \
  curl -s 'http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query?query=api:success_rate:5m'
```

Theo dõi alert:

```bash
kubectl get prometheusrule slo-alerts -n monitoring
kubectl run prom-alert-query --image=curlimages/curl:8.10.1 --rm -i --restart=Never -n monitoring -- \
  curl -s 'http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query?query=ALERTS%7Balertname%3D%22SLOViolation%22%7D'
```

Mở Alertmanager từ máy local:

```bash
cd terraform/ec2
terraform output -raw alertmanager_url
```

Kỳ vọng:

- Alert `SLOViolation` chuyển sang firing sau khi rule giữ điều kiện đủ `2m`.
- Nếu đã cấu hình email secret theo `app-alert/README.md`, Alertmanager gửi email.

### Reset sau các test

Đưa API về trạng thái không lỗi:

```bash
kubectl -n demo patch rollout api --type='json' \
  -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/env/0/value","value":"reset"},
    {"op":"replace","path":"/spec/template/spec/containers/0/env/1/value","value":"0"}
  ]'
```

Theo dõi rollout ổn định lại:

```bash
kubectl argo rollouts get rollout api -n demo --watch
```

Nếu muốn quay lại GitOps source đúng repo, sửa `app-api/rollout.yaml` trong repo,
commit, push rồi sync app `api` trong ArgoCD.

## Email alert

Tạo secret từ file mẫu:

```bash
cp app-alert/email-secret.yaml.example app-alert/email-secret.yaml
nano app-alert/email-secret.yaml
kubectl apply -f app-alert/email-secret.yaml
```

`email-secret.yaml` đã được ignore, không commit file này.

## Cleanup

Local Minikube:

```bash
kubectl delete -f argocd/root.yaml
kubectl delete ns argocd
minikube stop -p w10
minikube delete -p w10
```

AWS EC2:

```bash
cd terraform/ec2
terraform destroy
```

## Lưu ý bảo mật

- `terraform.tfvars`, Terraform state và private key local không được commit.
- `tls_private_key` lưu private key trong Terraform state, nên cần bảo vệ state.
- Nên giới hạn `ssh_allowed_cidr` và `lab_allowed_cidr` về public IP của bạn,
  không dùng `0.0.0.0/0` cho môi trường thật.
