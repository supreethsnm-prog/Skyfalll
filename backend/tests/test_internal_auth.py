from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app, verify_internal_api_key

client = TestClient(app)


def test_verify_internal_api_key_allows_when_no_key_configured(monkeypatch):
    # Calls the dependency function directly, in isolation — NOT through
    # the route/TestClient — specifically so this test never reaches the
    # real ingest route body (which would make a real SACHET network call).
    # Every other test in this project's suite avoids real network calls;
    # this is the one place doing so via TestClient would have broken that,
    # so the auth-open behavior is verified at the dependency-function
    # level instead.
    monkeypatch.setenv("INTERNAL_API_KEY", "")
    get_settings.cache_clear()
    try:
        result = verify_internal_api_key(x_internal_api_key=None)  # must not raise
        assert result is None
    finally:
        get_settings.cache_clear()


def test_ingest_alerts_rejects_missing_key_when_configured(monkeypatch):
    monkeypatch.setenv("INTERNAL_API_KEY", "test-secret-123")
    get_settings.cache_clear()
    try:
        response = client.post("/internal/ingest/alerts")
        assert response.status_code == 401
    finally:
        get_settings.cache_clear()


def test_ingest_alerts_rejects_wrong_key_when_configured(monkeypatch):
    monkeypatch.setenv("INTERNAL_API_KEY", "test-secret-123")
    get_settings.cache_clear()
    try:
        response = client.post(
            "/internal/ingest/alerts", headers={"X-Internal-API-Key": "wrong-key"}
        )
        assert response.status_code == 401
    finally:
        get_settings.cache_clear()


def test_ingest_marine_rejects_missing_key_when_configured(monkeypatch):
    monkeypatch.setenv("INTERNAL_API_KEY", "test-secret-123")
    get_settings.cache_clear()
    try:
        response = client.post("/internal/ingest/marine")
        assert response.status_code == 401
    finally:
        get_settings.cache_clear()
