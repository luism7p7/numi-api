FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app
COPY api/requirements.txt api/requirements.txt
RUN pip install --no-cache-dir -r api/requirements.txt && \
    pip install --no-cache-dir gunicorn==23.0.0
COPY . .
WORKDIR /app/api
EXPOSE 5000
# Una sola API para los dos paneles: /api/v1/auth, /api/v1/admin/..., /api/v1/docente/... y /api/app/v1/...
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:crear_app()"]
