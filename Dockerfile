# syntax=docker/dockerfile:1
# Base image pinned by digest; Dependabot proposes updates. Dependencies are installed from a
# hash-locked requirements file, so a tampered package fails the build.
FROM python:3.12-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
COPY app/requirements.txt .
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --require-hashes -r requirements.txt

FROM python:3.12-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b AS runtime
ARG APP_VERSION=dev
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    APP_VERSION=$APP_VERSION
LABEL org.opencontainers.image.title="secure-delivery-lab" \
      org.opencontainers.image.source="https://github.com/NathaliaGF/secure-delivery-lab" \
      org.opencontainers.image.licenses="MIT"
# Unprivileged user with a fixed UID, no shell, no home. The package manager is removed from
# the final image: it is not needed at runtime and only adds attack surface.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app \
 && python -m pip uninstall -y pip setuptools wheel >/dev/null 2>&1 || true
COPY --from=builder /opt/venv /opt/venv
WORKDIR /srv
COPY app/src/app ./app
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request as u, sys; sys.exit(0 if u.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status == 200 else 1)"]
# Heartbeat files go to /dev/shm so the root filesystem can be read-only.
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--worker-tmp-dir", "/dev/shm", "app.wsgi:app"]
