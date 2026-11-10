import json
import logging

import pytest

from app import MAX_MESSAGE_LEN, create_app


@pytest.fixture
def client():
    return create_app().test_client()


def test_index_reports_service_and_version(client):
    body = client.get("/").get_json()
    assert body["service"] == "secure-delivery-lab" and "version" in body


@pytest.mark.parametrize("path", ["/healthz", "/readyz"])
def test_probes_are_ok(client, path):
    resp = client.get(path)
    assert resp.status_code == 200 and resp.get_json()["status"] in {"ok", "ready"}


def test_security_headers_on_every_response(client):
    for path in ("/", "/nope"):
        h = client.get(path).headers
        assert h["X-Content-Type-Options"] == "nosniff"
        assert h["X-Frame-Options"] == "DENY"
        assert "default-src 'none'" in h["Content-Security-Policy"]
        assert h["Cache-Control"] == "no-store"


def test_request_id_is_generated_and_echoed(client):
    assert len(client.get("/").headers["X-Request-ID"]) == 32
    assert client.get("/", headers={"X-Request-ID": "abc-123"}).headers["X-Request-ID"] == "abc-123"


def test_echo_happy_path(client):
    resp = client.post("/api/echo", json={"message": "  hello  "})
    assert resp.status_code == 200 and resp.get_json() == {"message": "hello", "length": 5}


@pytest.mark.parametrize("payload", [None, [], {"message": 1}, {"msg": "x"}, "text"])
def test_echo_rejects_bad_shape(client, payload):
    resp = client.post("/api/echo", json=payload)
    assert resp.status_code == 400


@pytest.mark.parametrize("message", ["", "   ", "x" * (MAX_MESSAGE_LEN + 1)])
def test_echo_rejects_bad_length(client, message):
    assert client.post("/api/echo", json={"message": message}).status_code == 422


def test_echo_rejects_non_json_content(client):
    assert client.post("/api/echo", data="message=hi", content_type="text/plain").status_code == 400


def test_oversized_body_is_rejected(client):
    assert client.post("/api/echo", json={"message": "x" * 10_000}).status_code == 413


def test_wrong_method_and_unknown_route_return_json(client):
    assert client.get("/api/echo").status_code == 405
    assert client.get("/api/echo").get_json()["error"] == "method not allowed"
    assert client.get("/missing").get_json() == {"error": "not found"}


def test_metrics_expose_prometheus_text_and_count_requests(client):
    client.get("/healthz")
    client.get("/healthz")
    text = client.get("/metrics").get_data(as_text=True)
    assert 'app_http_requests_total{endpoint="healthz",method="GET",status="200"} 2.0' in text
    assert "app_http_request_duration_seconds_bucket" in text


def test_logs_are_json_and_do_not_include_scraper(capsys):
    logging.getLogger("app").handlers.clear()        # bind the handler to the captured stdout
    client = create_app().test_client()
    client.get("/healthz")
    client.get("/metrics")
    lines = [json.loads(l) for l in capsys.readouterr().out.splitlines() if l.strip()]
    paths = [l.get("path") for l in lines]
    assert "/healthz" in paths and "/metrics" not in paths
    entry = next(l for l in lines if l["path"] == "/healthz")
    assert entry["level"] == "INFO" and entry["status"] == 200 and "request_id" in entry
