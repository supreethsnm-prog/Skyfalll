from sqlalchemy import Column, DateTime, Float, Integer, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import declarative_base

Base = declarative_base()


class Alert(Base):
    __tablename__ = "alerts"

    id = Column(Integer, primary_key=True)
    external_id = Column(String, unique=True, nullable=False, index=True)
    source = Column(String, nullable=False)
    severity = Column(String, nullable=False)
    event_type = Column(String, nullable=False)
    area_description = Column(String, nullable=True)
    effective_start_time = Column(String, nullable=True)
    effective_end_time = Column(String, nullable=True)
    warning_message = Column(String, nullable=True)
    severity_color = Column(String, nullable=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)


class WeatherReading(Base):
    __tablename__ = "weather_readings"
    __table_args__ = (
        UniqueConstraint("latitude", "longitude", name="uq_weather_readings_lat_lon"),
    )

    id = Column(Integer, primary_key=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    temperature_c = Column(Float, nullable=False)
    humidity_pct = Column(Float, nullable=False)
    weather_code = Column(Integer, nullable=False)
    wind_speed_kmh = Column(Float, nullable=False)
    wind_direction_deg = Column(Float, nullable=False)
    observed_at = Column(String, nullable=False)
    timezone = Column(String, nullable=False)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)


class GeocodeCache(Base):
    __tablename__ = "geocode_cache"

    id = Column(Integer, primary_key=True)
    query = Column(String, unique=True, nullable=False)
    display_name = Column(String, nullable=False)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    country = Column(String, nullable=True)
    state = Column(String, nullable=True)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)


class MetarReading(Base):
    __tablename__ = "metar_readings"

    id = Column(Integer, primary_key=True)
    icao_id = Column(String, unique=True, nullable=False)
    raw_metar = Column(String, nullable=False)
    observed_at = Column(String, nullable=False)
    temperature_c = Column(Float, nullable=True)
    dewpoint_c = Column(Float, nullable=True)
    wind_dir_deg = Column(Float, nullable=True)
    wind_speed_kt = Column(Float, nullable=True)
    visibility_sm = Column(Float, nullable=True)
    flight_category = Column(String, nullable=True)
    station_name = Column(String, nullable=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)


class PfzZone(Base):
    __tablename__ = "pfz_zones"

    id = Column(Integer, primary_key=True)
    external_id = Column(String, unique=True, nullable=False)
    category = Column(String, nullable=True)
    sector_boundary = Column(Integer, nullable=True)
    sector_name = Column(String, nullable=True)
    julian_day = Column(String, nullable=True)
    serial_number = Column(String, nullable=True)
    year = Column(Integer, nullable=True)
    uid = Column(Integer, nullable=True)
    length_km = Column(Float, nullable=True)
    geometry = Column(JSONB, nullable=False)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)


class WeatherForecast(Base):
    __tablename__ = "weather_forecasts"
    __table_args__ = (
        UniqueConstraint(
            "latitude", "longitude", "forecast_date", name="uq_weather_forecasts_lat_lon_date"
        ),
    )

    id = Column(Integer, primary_key=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    forecast_date = Column(String, nullable=False)
    weather_code = Column(Integer, nullable=False)
    temp_max_c = Column(Float, nullable=False)
    temp_min_c = Column(Float, nullable=False)
    precip_probability_pct = Column(Float, nullable=True)
    precip_sum_mm = Column(Float, nullable=False)
    wind_speed_max_kmh = Column(Float, nullable=False)
    raw_payload = Column(JSONB, nullable=False)
    fetched_at = Column(DateTime(timezone=True), nullable=False)


class GfsForecastPoint(Base):
    __tablename__ = "gfs_forecast_points"
    __table_args__ = (
        UniqueConstraint(
            "run_date", "run_hour", "forecast_hour", "grid_latitude", "grid_longitude",
            name="uq_gfs_forecast_points_run_hour_point",
        ),
    )

    id = Column(Integer, primary_key=True)
    run_date = Column(String, nullable=False, index=True)
    run_hour = Column(String, nullable=False)
    forecast_hour = Column(Integer, nullable=False)
    valid_time = Column(DateTime(timezone=True), nullable=False)
    grid_latitude = Column(Float, nullable=False, index=True)
    grid_longitude = Column(Float, nullable=False, index=True)
    temp_2m_c = Column(Float, nullable=True)
    relative_humidity_2m_pct = Column(Float, nullable=True)
    wind_speed_10m_kmh = Column(Float, nullable=True)
    wind_direction_10m_deg = Column(Float, nullable=True)
    wind_gust_kmh = Column(Float, nullable=True)
    precip_rate_mmh = Column(Float, nullable=True)
    cape_j_per_kg = Column(Float, nullable=True)
    cin_j_per_kg = Column(Float, nullable=True)
    cloud_cover_pct = Column(Float, nullable=True)
    mslp_hpa = Column(Float, nullable=True)
    fetched_at = Column(DateTime(timezone=True), nullable=False)
