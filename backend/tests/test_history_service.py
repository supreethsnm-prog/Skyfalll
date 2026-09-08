from datetime import datetime, timezone

from sqlalchemy import insert

from app.db import get_engine
from app.history.service import get_historical_weather
from app.models import HistoricalWeatherReading


def _seed_row(**overrides):
    base = dict(
        location_name="Mumbai", latitude=19.08, longitude=72.88,
        observation_date="2023-07-15", temp_2m_c=27.3, dewpoint_2m_c=25.4,
        precip_mm=0.73, wind_speed_10m_kmh=16.0, wind_direction_10m_deg=247.3,
        mslp_hpa=1006.5, fetched_at=datetime.now(timezone.utc),
    )
    base.update(overrides)
    with get_engine().begin() as conn:
        conn.execute(insert(HistoricalWeatherReading).values(**base))


def test_returns_the_seeded_reading_for_an_exact_match(clean_historical_weather_readings):
    _seed_row()
    result = get_historical_weather("Mumbai", "2023-07-15")
    assert result is not None
    assert result["temp_2m_c"] == 27.3
    assert result["precip_mm"] == 0.73


def test_match_is_case_insensitive_on_location_name(clean_historical_weather_readings):
    _seed_row(location_name="Mumbai")
    result = get_historical_weather("mumbai", "2023-07-15")
    assert result is not None


def test_returns_none_for_an_unseeded_combination(clean_historical_weather_readings):
    _seed_row(location_name="Mumbai", observation_date="2023-07-15")
    assert get_historical_weather("Mumbai", "2023-07-16") is None
    assert get_historical_weather("Pune", "2023-07-15") is None


def test_no_raw_payload_or_id_in_response(clean_historical_weather_readings):
    _seed_row()
    result = get_historical_weather("Mumbai", "2023-07-15")
    assert "id" not in result
    assert "raw_payload" not in result
