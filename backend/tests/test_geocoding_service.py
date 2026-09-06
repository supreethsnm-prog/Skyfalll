from sqlalchemy import select

from app.db import get_engine
from app.geocoding.service import geocode_place
from app.models import GeocodeCache
from app.providers.geocoding import GeocodeResultData


class _RaisingProvider:
    def geocode(self, query):
        raise AssertionError("provider should not be called on a cache hit")


class _FakeGeocodingProvider:
    def __init__(self, result: GeocodeResultData | None):
        self._result = result
        self.calls = 0
        self.received_query = None

    def geocode(self, query):
        self.calls += 1
        self.received_query = query
        return self._result


def _sample_result(query="mumbai") -> GeocodeResultData:
    return GeocodeResultData(
        query=query,
        display_name="Mumbai, Maharashtra, India",
        latitude=19.0549990,
        longitude=72.8692035,
        country="India",
        state="Maharashtra",
        raw_payload={"name": "Mumbai"},
    )


def test_geocode_place_returns_cached_row_without_calling_provider(
    clean_geocode_cache,
):
    geocode_place("Mumbai", provider=_FakeGeocodingProvider(_sample_result()))

    result = geocode_place("Mumbai", provider=_RaisingProvider())

    assert result is not None
    assert result["display_name"] == "Mumbai, Maharashtra, India"
    assert "raw_payload" not in result


def test_geocode_place_normalizes_query_before_cache_lookup(clean_geocode_cache):
    geocode_place("  Mumbai  ", provider=_FakeGeocodingProvider(_sample_result()))

    result = geocode_place("MUMBAI", provider=_RaisingProvider())

    assert result is not None
    assert result["query"] == "mumbai"


def test_geocode_place_fetches_and_caches_on_missing_row(clean_geocode_cache):
    provider = _FakeGeocodingProvider(_sample_result())

    result = geocode_place("Mumbai", provider=provider)

    assert provider.calls == 1
    assert provider.received_query == "mumbai"
    assert result is not None
    assert result["latitude"] == 19.0549990

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(GeocodeCache).where(GeocodeCache.query == "mumbai")
        ).fetchall()
    assert len(rows) == 1


def test_geocode_place_returns_none_and_caches_nothing_when_not_found(
    clean_geocode_cache,
):
    provider = _FakeGeocodingProvider(None)

    result = geocode_place("zzznonexistentplacexyz123456", provider=provider)

    assert result is None
    assert provider.calls == 1

    with get_engine().connect() as conn:
        rows = conn.execute(select(GeocodeCache)).fetchall()
    assert len(rows) == 0
