# syntax=docker/dockerfile:1.7
# ============================================================================
# ETAPA 1 - builder: compila dependencias en un venv aislado.
# Nada de esta etapa llega a la imagen final salvo lo que copiemos explicito.
# ============================================================================
FROM python:3.12-slim AS builder

# Evita .pyc y buffering en logs (importante para kubectl logs)
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Toolchain de compilacion: SOLO existe en esta etapa
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copiamos primero los requirements para aprovechar la cache de capas:
# si el codigo cambia pero las dependencias no, esta capa se reutiliza.
COPY app/requirements.txt .

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir -r requirements.txt

# ============================================================================
# ETAPA 2 - tester: corre los tests DENTRO del build.
# Si un test falla, el build falla y nunca se publica la imagen.
# ============================================================================
FROM builder AS tester

COPY app/requirements-dev.txt .
RUN pip install --no-cache-dir -r requirements-dev.txt

COPY app/ ./app/
RUN python -m pytest app/tests -q && \
    bandit -r app -x app/tests -q && \
    ruff check app

# ============================================================================
# ETAPA 3 - runtime: imagen final minima.
# Sin compiladores, sin pytest, sin codigo de test, sin root.
# ============================================================================
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    APP_VERSION=1.0.0

# Usuario sin privilegios (requisito de securityContext en Kubernetes)
RUN groupadd --gid 10001 appgroup && \
    useradd --uid 10001 --gid appgroup --no-create-home --shell /sbin/nologin appuser

WORKDIR /srv

# Unico artefacto que traemos del builder: el venv ya compilado
COPY --from=builder /opt/venv /opt/venv

# Solo el codigo de produccion, sin tests
COPY --chown=appuser:appgroup app/main.py       ./app/main.py
COPY --chown=appuser:appgroup app/__init__.py   ./app/__init__.py

USER 10001

EXPOSE 8000

# Healthcheck a nivel imagen (complementa las probes de Kubernetes)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz',timeout=2).status==200 else 1)"

ENTRYPOINT ["uvicorn"]
CMD ["app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
