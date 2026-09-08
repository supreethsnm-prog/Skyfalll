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

# Operational choice, not an IMD figure: deliberately tighter than
# ``list_alerts``' own default radius_km=100.0 (see app/warning/service.py)
# because a city-scale advisory reasonably cares about a smaller neighbourhood
# than a general alert listing does. A deliberate divergence, not an oversight.
_ALERT_RADIUS_KM = 50.0

# Practical keyword filter (not an IMD taxonomy): the hazard families this
# Skill's own rules speak to, matched as substrings against a free-text
# ``event_type``. Kept broad on purpose — see ``_is_relevant_alert``, which errs
# toward inclusion rather than silently dropping an alert it cannot classify.
_ALERT_KEYWORDS = (
    "flood", "rain", "cyclone", "storm", "heat", "cold", "frost", "drought",
    "gale", "wind", "snow", "landslide", "lightning", "hail",
)

# Which relevant-alert keywords map onto which risk band, so an active alert
# can floor the matching band instead of coexisting with a LOW/UNKNOWN reading
# derived from the forecast alone.
_WATERLOGGING_ALERT_KEYWORDS = ("flood", "rain", "storm", "cyclone")
_HEAT_ALERT_KEYWORDS = ("heat",)
_WIND_ALERT_KEYWORDS = ("gale", "wind", "cyclone")


def _is_relevant_alert(alert: dict) -> bool:
    event_type = (alert.get("event_type") or "").lower()
    if not event_type:
        # Can't classify — err toward inclusion for a safety-relevant filter
        # rather than silently dropping an alert we can't categorize.
        return True
    return any(keyword in event_type for keyword in _ALERT_KEYWORDS)


def _alerts_match(alerts: list[dict], keywords: tuple[str, ...]) -> bool:
    return any(
        keyword in (a.get("event_type") or "").lower() for a in alerts for keyword in keywords
    )


def _raise_to_at_least_high(risk: str) -> str:
    """An active alert for this hazard makes anything below HIGH untrustworthy;
    a SEVERE forecast reading is never lowered."""
    return risk if risk == "SEVERE" else "HIGH"


def _waterlogging_risk(forecast_days: list[dict]) -> str:
    if not forecast_days:
        # No data is not the same as no risk — never report a confident LOW
        # built on an empty forecast.
        return "UNKNOWN"
    max_precip = max(d["precip_sum_mm"] for d in forecast_days)
    if max_precip >= _EXTREME_RAIN_MM:
        return "SEVERE"
    if max_precip >= _VERY_HEAVY_RAIN_MM:
        return "HIGH"
    if max_precip >= _HEAVY_RAIN_MM:
        return "MODERATE"
    return "LOW"


def _heat_risk(forecast_days: list[dict]) -> str:
    if not forecast_days:
        return "UNKNOWN"
    max_temp = max(d["temp_max_c"] for d in forecast_days)
    if max_temp >= _HEAT_SEVERE_C:
        return "SEVERE"
    if max_temp >= _HEAT_HIGH_C:
        return "HIGH"
    if max_temp >= _HEAT_MODERATE_C:
        return "MODERATE"
    return "LOW"


def _wind_risk(forecast_days: list[dict]) -> str:
    if not forecast_days:
        return "UNKNOWN"
    max_wind = max(d["wind_speed_max_kmh"] for d in forecast_days)
    return "HIGH" if max_wind >= _GALE_KMH else "LOW"


def get_urban_advisory(latitude: float, longitude: float, days: int = 5) -> dict:
    forecast_days = get_forecast(latitude, longitude, days=days)
    alerts = list_alerts(latitude=latitude, longitude=longitude, radius_km=_ALERT_RADIUS_KM)

    waterlogging_risk = _waterlogging_risk(forecast_days)
    heat_risk = _heat_risk(forecast_days)
    wind_risk = _wind_risk(forecast_days)

    relevant_alerts = [a for a in alerts if _is_relevant_alert(a)]

    # An active alert for a hazard outranks the forecast-derived band: the band
    # is floored before any advisory text is generated, so the two can never
    # disagree in the response.
    if _alerts_match(relevant_alerts, _WATERLOGGING_ALERT_KEYWORDS):
        waterlogging_risk = _raise_to_at_least_high(waterlogging_risk)
    if _alerts_match(relevant_alerts, _HEAT_ALERT_KEYWORDS):
        heat_risk = _raise_to_at_least_high(heat_risk)
    if _alerts_match(relevant_alerts, _WIND_ALERT_KEYWORDS):
        wind_risk = _raise_to_at_least_high(wind_risk)

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
            "High wind risk — gale-force winds (>=62 km/h) possible; secure loose "
            "structures and hoardings, and check tree/power-line risk areas."
        )

    if "UNKNOWN" in (waterlogging_risk, heat_risk, wind_risk):
        advisories.append(
            "Forecast data unavailable — risk assessment could not be completed."
        )

    if relevant_alerts:
        advisories.append(
            f"{len(relevant_alerts)} active weather alert(s) within "
            f"{_ALERT_RADIUS_KM:.0f}km — see active_alerts for details."
        )

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
