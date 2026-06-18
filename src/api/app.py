import os
import random

from flask import Flask, jsonify
from prometheus_flask_exporter import PrometheusMetrics

# Flask API nhỏ dùng làm workload demo cho canary rollout.
# Ứng dụng cố tình có thể inject lỗi bằng biến môi trường ERROR_RATE để test:
# - canary thành công khi error rate thấp
# - canary fail/rollback khi error rate cao
# - Prometheus alert khi success rate thấp hơn SLO
app = Flask(__name__)

# prometheus-flask-exporter tự đăng ký endpoint /metrics và expose metric
# flask_http_request_duration_seconds_count. AnalysisTemplate và PrometheusRule
# trong lab query metric này để tính success rate.
PrometheusMetrics(app)

# ERROR_RATE là xác suất endpoint "/" trả HTTP 500.
# Giá trị này được cấu hình trong app-api/rollout.yaml để mô phỏng lỗi runtime.
ERROR_RATE = float(os.getenv("ERROR_RATE", "0"))

# VERSION giúp phân biệt version đang được rollout khi quan sát response API.
VERSION = os.getenv("VERSION", "v1")


@app.get("/")
def index():
    """Endpoint chính của API, có thể trả lỗi giả lập theo ERROR_RATE."""
    if random.random() < ERROR_RATE:
        return jsonify(error="injected", version=VERSION), 500
    return jsonify(ok=True, version=VERSION)


@app.get("/healthz")
def healthz():
    """Endpoint health check cho Kubernetes liveness/readiness probe."""
    return "ok", 200


if __name__ == "__main__":
    # Chạy trực tiếp khi debug local; container production trong Dockerfile dùng
    # "flask run" nhưng vẫn giữ block này để app.py tự chạy được khi cần.
    app.run(host="0.0.0.0", port=8080)
