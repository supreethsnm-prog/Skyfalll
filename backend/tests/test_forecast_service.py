from datetime import datetime, timedelta, timezone

from sqlalchemy import insert, select

from app.db import get_engine
from app.forecast.service import get_forecast
from app.models import WeatherForecast
from app.providers.weather import ForecastDayData


class _FakeForecastProvider:
    def __init__(self, days: list[ForecastDayData]):
        self._days = days
        self.calls = 0

    def fetch_forecast(self, latitude, longitude, days):
        self.calls += 1
        return self._days


def _sample_day(forecast_date="2026-09-08", temp_max_c=29.0):
    return ForecastDayData(
        latitude=19.08, longitude=72.88, forecast_date=forecast_date, weather_code=51,
        temp_max_c=temp_max_c, temp_min_c=25.0, precip_probability_pct=90.0,
        precip_sum_mm=3.0, wind_speed_max_kmh=14.0, raw_payload={"live": True},
    )


def test_get_forecast_fetches_and_caches_on_missing_rows(clean_weather_forecasts):
    provider = _FakeForecastProvider([_sample_day()])

    result = get_forecast(19.08, 72.88, days=1, provider=provider)

    assert provider.calls == 1
    assert result[0]["temp_max_c"] == 29.0
    assert "raw_payload" not in result[0]

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(WeatherForecast).where(
                WeatherForecast.latitude == 19.08, WeatherForecast.longitude == 72.88
            )
        ).fetchall()
    assert len(rows) == 1


def test_get_forecast_returns_fresh_cache_without_calling_provider(clean_weather_forecasts):
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherForecast).values(
                latitude=19.08, longitude=72.88, forecast_date="2026-09-08", weather_code=51,
                temp_max_c=30.0, temp_min_c=25.0, precip_probability_pct=50.0,
                precip_sum_mm=1.0, wind_speed_max_kmh=10.0, raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )

    class _RaisingProvider:
        def fetch_forecast(self, latitude, longitude, days):
            raise AssertionError("provider should not be called on a fresh cache hit")

    result = get_forecast(19.08, 72.88, days=1, provider=_RaisingProvider())

    assert result[0]["temp_max_c"] == 30.0


def test_get_forecast_refetches_when_cache_is_stale(clean_weather_forecasts):
    stale_time = datetime.now(timezone.utc) - timedelta(minutes=30)
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherForecast).values(
                latitude=19.08, longitude=72.88, forecast_date="2026-09-08", weather_code=51,
                temp_max_c=10.0, temp_min_c=5.0, precip_probability_pct=50.0,
                precip_sum_mm=1.0, wind_speed_max_kmh=10.0, raw_payload={"stale": True},
                fetched_at=stale_time,
            )
        )
    provider = _FakeForecastProvider([_sample_day(temp_max_c=35.0)])

    result = get_forecast(19.08, 72.88, days=1, provider=provider)

    assert provider.calls == 1
    assert result[0]["temp_max_c"] == 35.0


def test_get_forecast_rounds_coordinates_for_cache_key(clean_weather_forecasts):
    provider = _FakeForecastProvider([_sample_day()])

    get_forecast(19.0761, 72.8812, days=1, provider=provider)

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(WeatherForecast).where(
                WeatherForecast.latitude == 19.08, WeatherForecast.longitude == 72.88
            )
        ).fetchall()
    assert len(rows) == 1


class _RaisingForecastProvider:
    def fetch_forecast(self, latitude, longitude, days):
        raise RuntimeError("provider unavailable")


def test_get_forecast_falls_back_to_full_stale_cache_on_provider_error(clean_weather_forecasts):
    stale_time = datetime.now(timezone.utc) - timedelta(minutes=30)
    with get_engine().begin() as conn:
        for forecast_date, temp_max_c in (("2026-09-08", 20.0), ("2026-09-09", 21.0)):
            conn.execute(
                insert(WeatherForecast).values(
                    latitude=19.08, longitude=72.88, forecast_date=forecast_date, weather_code=51,
                    temp_max_c=temp_max_c, temp_min_c=15.0, precip_probability_pct=50.0,
                    precip_sum_mm=1.0, wind_speed_max_kmh=10.0, raw_payload={"stale": True},
                    fetched_at=stale_time,
                )
            )

    result = get_forecast(19.08, 72.88, days=2, provider=_RaisingForecastProvider())

    assert len(result) == 2
    assert {r["forecast_date"] for r in result} == {"2026-09-08", "2026-09-09"}


def test_get_forecast_falls_back_to_partial_stale_cache_on_provider_error(clean_weather_forecasts):
    stale_time = datetime.now(timezone.utc) - timedelta(minutes=30)
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherForecast).values(
                latitude=19.08, longitude=72.88, forecast_date="2026-09-08", weather_code=51,
                temp_max_c=20.0, temp_min_c=15.0, precip_probability_pct=50.0,
                precip_sum_mm=1.0, wind_speed_max_kmh=10.0, raw_payload={"stale": True},
                fetched_at=stale_time,
            )
        )

    result = get_forecast(19.08, 72.88, days=3, provider=_RaisingForecastProvider())

    assert len(result) == 1
    assert result[0]["forecast_date"] == "2026-09-08"


def test_get_forecast_upserts_multiple_days_without_duplicating(clean_weather_forecasts):
    day1 = _sample_day(forecast_date="2026-09-08", temp_max_c=29.0)
    day2 = _sample_day(forecast_date="2026-09-09", temp_max_c=30.0)
    provider = _FakeForecastProvider([day1, day2])

    get_forecast(19.08, 72.88, days=2, provider=provider)
    # Re-fetch immediately (still fresh) with a different provider whose
    # data must NOT be used, then re-fetch after forcing staleness.
    result = get_forecast(19.08, 72.88, days=2, provider=_FakeForecastProvider([day1, day2]))

    assert len(result) == 2
    assert {r["forecast_date"] for r in result} == {"2026-09-08", "2026-09-09"}

    with get_engine().connect() as conn:
        rows = conn.execute(
            select(WeatherForecast).where(
                WeatherForecast.latitude == 19.08, WeatherForecast.longitude == 72.88
            )
        ).fetchall()
    assert len(rows) == 2
