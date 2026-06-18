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

#### 4. Test API

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
kubectl -n demo run curl-api --image=curlimages/curl:latest --rm -i --restart=Never -- \
  curl -s http://api.demo.svc.cluster.local/healthz
```

#### 5. Truy cập các UI và endpoint public

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

#### 6. Đọc file hướng dẫn nhanh trên EC2

Bootstrap tạo sẵn file này trong EC2:

```bash
cat /home/ec2-user/w10-lab-info.txt
```

File này nhắc lại các lệnh kiểm tra thường dùng và danh sách port đang expose.

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

### Test 1: Canary thành công

Sửa `ERROR_RATE` trong `app-api/rollout.yaml`:

```yaml
- name: ERROR_RATE
  value: "0"
```

Commit và push:

```bash
git add app-api/rollout.yaml
git commit -m "test: deploy with 0 percent error rate"
git push origin main
```

Theo dõi:

```bash
kubectl get rollout api -n demo -w
kubectl get analysisrun -n demo
```

Kỳ vọng: Rollout đi tới `Healthy`, AnalysisRun pass vì success rate đạt ngưỡng.

### Test 2: Canary fail và rollback

Sửa `ERROR_RATE`:

```yaml
- name: ERROR_RATE
  value: "0.15"
```

Commit và push:

```bash
git add app-api/rollout.yaml
git commit -m "test: deploy with 15 percent error rate"
git push origin main
```

Theo dõi:

```bash
kubectl get analysisrun -n demo -w
kubectl get rollout api -n demo
```

Kỳ vọng: AnalysisRun fail khi success rate thấp, Rollout không promote version
mới và tự rollback theo cơ chế của Argo Rollouts.

### Test 3: Trigger SLO alert

Sửa `ERROR_RATE`:

```yaml
- name: ERROR_RATE
  value: "0.10"
```

Canary vẫn có thể pass nếu ngưỡng analysis là `>= 90%`, nhưng alert SLO sẽ fire
khi success rate thấp hơn `95%` trong rule `app-alert/prometheus-rules.yaml`.

Theo dõi alert:

```bash
kubectl get prometheusrule -n monitoring
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

Nếu chạy trên EC2, có thể dùng luôn `terraform output -raw alertmanager_url` từ
máy local để mở Alertmanager.

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
