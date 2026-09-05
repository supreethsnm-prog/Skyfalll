from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_db_returns_connected():
    response = client.get("/health/db")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "db": "connected"}
