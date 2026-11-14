# syntax=docker/dockerfile:1.7
#
# Multi-stage image for the AI Ticket Resolution System.
#   Stage 1 builds the React/Vite frontend.
#   Stage 2 is a slim Python runtime: FastAPI serves the API and the built SPA
#   (the app looks for ../frontend/dist relative to backend/, so the layout
#   /app/backend + /app/frontend/dist is intentional).
#
# Build from the repository root:
#   docker build -f docker/Dockerfile -t ticket-resolution:dev .

# ---------- Stage 1: frontend build ----------
FROM node:22-slim AS frontend-build
WORKDIR /build/frontend

# Override to e.g. "npx vite build" if upstream type-checking (tsc -b) blocks a build.
ARG FRONTEND_BUILD_CMD="npm run build"

COPY app/frontend/package.json app/frontend/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm install --no-audit --no-fund

COPY app/frontend/ ./
RUN sh -c "${FRONTEND_BUILD_CMD}"

# ---------- Stage 2: runtime ----------
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=8000

# Non-root user
RUN groupadd --system --gid 10001 app \
 && useradd  --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app

WORKDIR /app/backend

COPY app/backend/requirements.txt ./
RUN pip install -r requirements.txt

COPY app/backend/ ./
COPY --from=frontend-build /build/frontend/dist /app/frontend/dist
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
 && chown -R app:app /app

USER app
EXPOSE 8000

# /health returns 503 until the knowledge base is loaded, so this doubles as a readiness gate.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD python -c "import os,sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT','8000'), timeout=4).status == 200 else 1)"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sh", "-c", "exec uvicorn app:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips='*'"]
