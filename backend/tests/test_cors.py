from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_allowed_origin_gets_cors_header():
    response = client.get("/health", headers={"Origin": "http://localhost:3000"})
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:3000"


def test_disallowed_origin_does_not_get_cors_header():
    response = client.get("/health", headers={"Origin": "http://evil.example.com"})
    assert response.status_code == 200  # the request itself still succeeds...
    assert "access-control-allow-origin" not in response.headers  # ...but isn't CORS-approved


def test_credentials_are_not_enabled():
    response = client.get("/health", headers={"Origin": "http://localhost:3000"})
    assert "access-control-allow-credentials" not in response.headers
