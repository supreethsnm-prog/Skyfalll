from fastapi.testclient import TestClient

from app.geocoding.service import geocode_place
from app.main import app
from app.providers.geocoding import GeocodeResultData

client = TestClient(app)


class _FakeGeocodingProvider:
    def __init__(self, result):
        self._result = result

    def geocode(self, query):
        return self._result


def test_geocode_endpoint_returns_cached_result(clean_geocode_cache):
    geocode_place(
        "Mumbai",
        provider=_FakeGeocodingProvider(
            GeocodeResultData(
                query="mumbai",
                display_name="Mumbai, Maharashtra, India",
                latitude=19.0549990,
                longitude=72.8692035,
                country="India",
                state="Maharashtra",
                raw_payload={"name": "Mumbai"},
            )
        ),
    )

    response = client.get("/geocode", params={"q": "Mumbai"})

    assert response.status_code == 200
    body = response.json()
    assert body["display_name"] == "Mumbai, Maharashtra, India"
    assert "raw_payload" not in body


def test_geocode_endpoint_returns_404_when_not_found(monkeypatch):
    monkeypatch.setattr("app.main.geocode_place", lambda q: None)

    response = client.get(
        "/geocode", params={"q": "zzznonexistentplacexyz123456notcached"}
    )

    assert response.status_code == 404
