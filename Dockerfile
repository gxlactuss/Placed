# Build context is the REPO ROOT so both `backend/` and the sibling `database/`
# package are available. Python 3.12 matches the union-type syntax the app uses.
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Install deps first so the layer caches across code-only changes.
COPY backend/requirements.txt .
RUN pip install -r requirements.txt

# The backend app and the standalone database package sit side by side under
# /app, so `app` and `database` are both importable (see backend/app/__init__.py).
COPY database ./database
COPY backend/app ./app

# Fly routes to this internal port (see fly.toml http_service.internal_port).
EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
