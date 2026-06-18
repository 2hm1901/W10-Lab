# Image runtime nhỏ cho Flask API của lab.
# Alpine đủ nhẹ cho demo, còn python:3.13 giúp chạy app.py không cần cài Python
# trực tiếp trên node Kubernetes/EC2.
FROM python:3.13-alpine

# Cài Flask và exporter để app tự expose /metrics cho Prometheus scrape.
RUN pip install flask prometheus-flask-exporter

# Copy đúng file app.py vào thư mục runtime trong container.
COPY app.py /app/app.py
WORKDIR /app

# Flask CLI cần FLASK_APP để biết module ứng dụng.
ENV FLASK_APP=app.py

# Container listen cổng 8080; Kubernetes Service map port 80 -> targetPort 8080.
EXPOSE 8080

# Bind 0.0.0.0 để request từ bên ngoài container/pod có thể vào được.
CMD ["flask", "run", "--host=0.0.0.0", "--port=8080"]
