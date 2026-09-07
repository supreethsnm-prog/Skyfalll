"""Rules-based urban-planning advisory Skill (spec section 4: "Urban
planning / smart city monitoring" — a Skill, not a data source). Same
pattern as app/skills/agriculture.py: combines already-ingested forecast
and alert data through a deterministic ruleset, never an LLM guess.
"""

from datetime import datetime, timezone

from app.forecast.service import get_forecast
from app.warning.service import list_alerts

# IMD's 24-hour rainfall intensity classification (imd.gov.in glossary) —
# same source and thresholds as app/skills/agriculture.py.
_HEAVY_RAIN_MM = 64.5
_VERY_HEAVY_RAIN_MM = 115.6
_EXTREME_RAIN_MM = 204.4

# Heat-risk bands loosely following IMD heat wave criteria for the plains
# (heat wave >=40C, severe heat wave >=45C) plus a lower "watch" band.
_HEAT_MODERATE_C = 35.0
_HEAT_HIGH_C = 40.0
_HEAT_SEVERE_C = 45.0

# IMD's "gale" wind-speed threshold is approximately 62 km/h (34 knots).
_GALE_KMH = 62.0

_ALERT_RADIUS_KM = 50.0
_ALERT_KEYWORDS = ("flood", "rain", "cyclone", "storm", "heat")


def _waterlogging_risk(forecast_days: list[dict]) -> str:
    max_precip = max((d["precip_sum_mm"] for d in forecast_days), default=0.0)
    if max_precip >= _EXTREME_RAIN_MM:
        return "SEVERE"
    if max_precip >= _VERY_HEAVY_RAIN_MM:
        return "HIGH"
    if max_precip >= _HEAVY_RAIN_MM:
        return "MODERATE"
    return "LOW"


def _heat_risk(forecast_days: list[dict]) -> str:
    max_temp = max((d["temp_max_c"] for d in forecast_days), default=0.0)
    if max_temp >= _HEAT_SEVERE_C:
        return "SEVERE"
    if max_temp >= _HEAT_HIGH_C:
        return "HIGH"
    if max_temp >= _HEAT_MODERATE_C:
        return "MODERATE"
    return "LOW"


def _wind_risk(forecast_days: list[dict]) -> str:
    max_wind = max((d["wind_speed_max_kmh"] for d in forecast_days), default=0.0)
    return "HIGH" if max_wind >= _GALE_KMH else "LOW"


def get_urban_advisory(latitude: float, longitude: float, days: int = 5) -> dict:
    forecast_days = get_forecast(latitude, longitude, days=days)
    alerts = list_alerts(latitude=latitude, longitude=longitude, radius_km=_ALERT_RADIUS_KM)

    waterlogging_risk = _waterlogging_risk(forecast_days)
    heat_risk = _heat_risk(forecast_days)
    wind_risk = _wind_risk(forecast_days)

    advisories: list[str] = []
    if waterlogging_risk in ("HIGH", "SEVERE"):
        advisories.append(
            "High waterlogging risk — check stormwater drains and low-lying areas; "
            "avoid non-essential travel during heavy rain."
        )
    elif waterlogging_risk == "MODERATE":
        advisories.append("Moderate waterlogging risk — monitor local drainage in low-lying areas.")

    if heat_risk in ("HIGH", "SEVERE"):
        advisories.append(
            "High heat risk — activate cooling shelters/hydration points, advise outdoor "
            "workers to avoid midday exposure."
        )

    if wind_risk == "HIGH":
        advisories.append(
            "Gale-force winds forecast (>=62 km/h) — secure loose structures and hoardings, "
            "and check tree/power-line risk areas."
        )

    relevant_alerts = [
        a for a in alerts if any(keyword in a["event_type"].lower() for keyword in _ALERT_KEYWORDS)
    ]

    return {
        "latitude": latitude,
        "longitude": longitude,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "risk_summary": {
            "waterlogging_risk": waterlogging_risk,
            "heat_risk": heat_risk,
            "wind_risk": wind_risk,
        },
        "advisories": advisories,
        "active_alerts": relevant_alerts,
        "forecast_basis": forecast_days,
    }
