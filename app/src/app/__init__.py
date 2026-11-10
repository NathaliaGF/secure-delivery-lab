"""A deliberately small service used as the payload of the delivery pipeline.

It exposes health probes, Prometheus metrics, JSON logs and security headers, so the pipeline,
the container hardening and the observability stack have something real to deliver and watch.
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time
import uuid

from flask import Flask, Response, g, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, CollectorRegistry, Counter, Histogram, generate_latest

__version__ = os.environ.get("APP_VERSION", "dev")

MAX_MESSAGE_LEN = 280

_SECURITY_HEADERS = {
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cache-Control": "no-store",
}


class JsonFormatter(logging.Formatter):
    """One JSON object per line, ready for any log shipper."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created)) + "Z",
            "level": record.levelname,
            "msg": record.getMessage(),
        }
        payload.update(getattr(record, "fields", {}))
        return json.dumps(payload, separators=(",", ":"))


def _configure_logging() -> logging.Logger:
    logger = logging.getLogger("app")
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(JsonFormatter())
        logger.addHandler(handler)
        logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())
        logger.propagate = False
    return logger


def create_app() -> Flask:
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = 4 * 1024      # reject large bodies before parsing
    log = _configure_logging()

    # One registry per app so tests can build several apps in one process.
    registry = CollectorRegistry()
    requests_total = Counter("app_http_requests_total", "HTTP requests",
                             ["method", "endpoint", "status"], registry=registry)
    latency = Histogram("app_http_request_duration_seconds", "Request latency in seconds",
                        ["endpoint"], registry=registry)

    @app.before_request
    def _start() -> None:
        g.started = time.perf_counter()
        g.request_id = request.headers.get("X-Request-ID") or uuid.uuid4().hex

    @app.after_request
    def _finish(resp: Response) -> Response:
        elapsed = time.perf_counter() - g.get("started", time.perf_counter())
        endpoint = request.endpoint or "unmatched"
        requests_total.labels(request.method, endpoint, resp.status_code).inc()
        latency.labels(endpoint).observe(elapsed)
        for k, v in _SECURITY_HEADERS.items():
            resp.headers.setdefault(k, v)
        resp.headers["X-Request-ID"] = g.get("request_id", "")
        if endpoint != "metrics":                       # do not log the scraper every 15 s
            log.info("request", extra={"fields": {
                "request_id": g.get("request_id"), "method": request.method, "path": request.path,
                "status": resp.status_code, "duration_ms": round(elapsed * 1000, 2),
            }})
        return resp

    @app.get("/")
    def index():
        return jsonify(service="secure-delivery-lab", version=__version__)

    @app.get("/healthz")
    def healthz():
        return jsonify(status="ok")

    @app.get("/readyz")
    def readyz():
        return jsonify(status="ready")

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(registry), mimetype=CONTENT_TYPE_LATEST)

    @app.post("/api/echo")
    def echo():
        body = request.get_json(silent=True)
        if not isinstance(body, dict) or not isinstance(body.get("message"), str):
            return jsonify(error="expected JSON object with a string 'message'"), 400
        message = body["message"].strip()
        if not message or len(message) > MAX_MESSAGE_LEN:
            return jsonify(error=f"'message' must be 1-{MAX_MESSAGE_LEN} characters"), 422
        return jsonify(message=message, length=len(message))

    @app.errorhandler(404)
    def not_found(_e):
        return jsonify(error="not found"), 404

    @app.errorhandler(413)
    def too_large(_e):
        return jsonify(error="payload too large"), 413

    @app.errorhandler(405)
    def method_not_allowed(_e):
        return jsonify(error="method not allowed"), 405

    return app
