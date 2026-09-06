from datetime import datetime, timedelta, timezone

from sqlalchemy import insert, select

from app.aviation.service import get_metar
from app.db import get_engine
from app.models import MetarReading
from app.providers.aviation import MetarReadingData


class _RaisingProvider:
    def fetch_metar(self, icao_id):
        raise AssertionError("provider should not be called on a fresh cache hit")


class _FakeAviationProvider:
    def __init__(self, reading: MetarReadingData | None, exc: Exception | None = None):
        self._reading = reading
        self._exc = exc
        self.calls = 0

    def fetch_metar(self, icao_id):
        self.calls += 1
        if self._exc is not None:
            raise self._exc
        return self._reading


def _sample_reading(icao_id="VABB", temperature_c=30.0) -> MetarReadingData:
    return MetarReadingData(
        icao_id=icao_id,
        raw_metar="METAR VABB 060900Z 28012KT 3000 BR SCT018 BKN090 30/25 Q1011 NOSIG",
        observed_at="2026-09-06T09:00:00.000Z",
        temperature_c=temperature_c,
        dewpoint_c=25.0,
        wind_dir_deg=280.0,
        wind_speed_kt=12.0,
        visibility_sm=1.86,
        flight_category="IFR",
        station_name="Mumbai/Shivaji Intl, MM, IN",
        latitude=19.1,
        longitude=72.859,
        raw_payload={"icaoId": icao_id},
    )


def _seed_reading(fetched_at, icao_id="VABB", temperature_c=30.0):
    reading = _sample_reading(icao_id, temperature_c)
    with get_engine().begin() as conn:
        conn.execute(
            insert(MetarReading).values(
                icao_id=reading.icao_id,
                raw_metar=reading.raw_metar,
                observed_at=reading.observed_at,
                temperature_c=reading.temperature_c,
                dewpoint_c=reading.dewpoint_c,
                wind_dir_deg=reading.wind_dir_deg,
                wind_speed_kt=reading.wind_speed_kt,
                visibility_sm=reading.visibility_sm,
                flight_category=reading.flight_category,
                station_name=reading.station_name,
                latitude=reading.latitude,
                longitude=reading.longitude,
                raw_payload=reading.raw_payload,
                fetched_at=fetched_at,
            )
        )


def test_get_metar_returns_fresh_cache_without_calling_provider(clean_metar_readings):
    _seed_reading(fetched_at=datetime.now(timezone.utc))

    result = get_metar("VABB", provider=_RaisingProvider())

    assert result["temperature_c"] == 30.0
    assert "raw_payload" not in result


def test_get_metar_fetches_and_caches_on_missing_row(clean_metar_readings):
    provider = _FakeAviationProvider(_sample_reading())

    result = get_metar("VABB", provider=provider)

    assert provider.calls == 1
    assert result["temperature_c"] == 30.0
    assert "raw_payload" not in result

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(MetarReading).where(MetarReading.icao_id == "VABB")
        ).fetchall()
    assert len(rows) == 1


def test_get_metar_refetches_when_cache_is_stale(clean_metar_readings):
    stale_time = datetime.now(timezone.utc) - timedelta(minutes=30)
    _seed_reading(fetched_at=stale_time, temperature_c=10.0)

    provider = _FakeAviationProvider(_sample_reading(temperature_c=32.0))

    result = get_metar("VABB", provider=provider)

    assert provider.calls == 1
    assert result["temperature_c"] == 32.0

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(MetarReading).where(MetarReading.icao_id == "VABB")
        ).fetchall()
    assert len(rows) == 1
    assert rows[0].temperature_c == 32.0


def test_get_metar_serves_stale_cache_when_live_fetch_fails(clean_metar_readings):
    stale_time = datetime.now(timezone.utc) - timedelta(minutes=30)
    _seed_reading(fetched_at=stale_time, temperature_c=10.0)

    provider = _FakeAviationProvider(None, exc=ConnectionError("network down"))

    result = get_metar("VABB", provider=provider)

    assert provider.calls == 1
    assert result["temperature_c"] == 10.0


def test_get_metar_normalizes_icao_id_to_uppercase(clean_metar_readings):
    _seed_reading(fetched_at=datetime.now(timezone.utc), icao_id="VABB")

    result = get_metar("vabb", provider=_RaisingProvider())

    assert result is not None
    assert result["icao_id"] == "VABB"


def test_get_metar_returns_none_when_station_has_no_data(clean_metar_readings):
    provider = _FakeAviationProvider(None)

    result = get_metar("ZZZZ", provider=provider)

    assert result is None
    assert provider.calls == 1

    with get_engine().connect() as conn:
        rows = conn.execute(select(MetarReading)).fetchall()
    assert len(rows) == 0
