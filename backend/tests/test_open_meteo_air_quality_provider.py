import httpx
import pytest

from app.providers.open_meteo_air_quality import OpenMeteoAirQualityProvider

SAMPLE_RESPONSE = {
    "latitude": 28.625,
    "longitude": 77.25,
    "timezone": "Asia/Kolkata",
    "current": {
        "time": "2026-09-09T14:00",
        "us_aqi": 156,
        "pm2_5": 64.8,
        "pm10": 118.2,
    },
}


def _provider_returning(payload, status=200):
    def handler(request):
        return httpx.Response(status, json=payload)

    return OpenMeteoAirQualityProvider(
        client=httpx.Client(transport=httpx.MockTransport(handler))
    )


def test_fetch_current_normalizes_response():
    reading = _provider_returning(SAMPLE_RESPONSE).fetch_current(28.61, 77.21)

    assert reading.us_aqi == 156
    assert reading.pm2_5 == 64.8
    assert reading.pm10 == 118.2
    assert reading.observed_at == "2026-09-09T14:00"
    assert reading.raw_payload == SAMPLE_RESPONSE


def test_fetch_current_preserves_requested_coordinates():
    # Upstream snaps to its grid (28.625/77.25 above). The caller's own
    # coordinates are what the cache is keyed on, so they must survive —
    # this mirrors OpenMeteoWeatherProvider's documented behaviour.
    reading = _provider_returning(SAMPLE_RESPONSE).fetch_current(28.61, 77.21)

    assert reading.latitude == 28.61
    assert reading.longitude == 77.21


def test_fetch_current_tolerates_missing_pollutants():
    payload = {"current": {"time": "2026-09-09T14:00"}}

    reading = _provider_returning(payload).fetch_current(28.61, 77.21)

    assert reading.us_aqi is None
    assert reading.pm2_5 is None
    assert reading.pm10 is None
    assert reading.observed_at == "2026-09-09T14:00"


def test_fetch_current_requests_the_pollutant_fields():
    seen = {}

    def handler(request):
        seen.update(dict(request.url.params))
        return httpx.Response(200, json=SAMPLE_RESPONSE)

    provider = OpenMeteoAirQualityProvider(
        client=httpx.Client(transport=httpx.MockTransport(handler))
    )
    provider.fetch_current(28.61, 77.21)

    for field in ("us_aqi", "pm2_5", "pm10"):
        assert field in seen["current"], f"{field} missing from current="
    assert float(seen["latitude"]) == 28.61
    assert float(seen["longitude"]) == 77.21


def test_fetch_current_raises_on_upstream_error():
    # Matches OpenMeteoWeatherProvider, which lets raise_for_status through
    # so the service layer can decide whether to serve a stale row.
    with pytest.raises(httpx.HTTPStatusError):
        _provider_returning({"error": True}, status=503).fetch_current(28.61, 77.21)


def test_fetch_current_raises_on_unparseable_payload():
    with pytest.raises((KeyError, TypeError)):
        _provider_returning({"unexpected": "shape"}).fetch_current(28.61, 77.21)
