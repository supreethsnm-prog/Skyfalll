"""Rules-based agriculture advisory Skill (spec section 4: "Agriculture
advisory" — a Skill, not a data source, since no public IMD Agromet API
exists to redistribute). Combines already-ingested forecast and alert data
through a small, explicit ruleset; the LLM verbalizes this structured
result but never invents the thresholds itself — the same grounding
principle (spec section 1) that every chat tool already enforces for raw
facts, applied here to a derived advisory instead.

Thresholds are drawn from IMD's own published classifications, not
invented — see the inline citation on each constant below.
"""

from datetime import datetime, timezone

from app.forecast.service import get_forecast
from app.warning.service import list_alerts

# IMD's 24-hour rainfall intensity classification (imd.gov.in glossary):
# light 2.5-15.5mm, moderate 15.6-64.4mm, heavy 64.5-115.5mm,
# very heavy 115.6-204.4mm, extremely heavy >204.4mm.
_HEAVY_RAIN_MM = 64.5
_VERY_HEAVY_RAIN_MM = 115.6

# IMD heat wave criteria for the plains: heat wave when max temp >= 40C,
# severe heat wave >= 45C. Used here as a field heat-stress threshold, not
# a formal IMD heat wave declaration (that also requires a
# departure-from-normal check this Skill has no baseline data for).
_HEAT_STRESS_C = 40.0
_SEVERE_HEAT_STRESS_C = 45.0

# Frost risk for standing Rabi-season crops is commonly flagged once
# overnight minimum temperature approaches 4C near ground level.
_FROST_RISK_C = 4.0

_DRY_SPELL_PRECIP_PROBABILITY_PCT = 20.0

_ALERT_RADIUS_KM = 50.0

_ALERT_KEYWORDS = ("flood", "rain", "cyclone", "storm", "heat")

# Illustrative, non-exhaustive crop-specific notes — not authoritative
# agronomic guidance, only a starting point for the advisory text.
_CROP_NOTES = {
    "rice": (
        "Standing water is tolerated, but ensure field drainage if heavy rain is "
        "forecast to prevent root rot."
    ),
    "wheat": (
        "Frost below 4C can damage standing wheat during flowering/grain-filling — "
        "consider light irrigation the evening before a forecast cold night, which "
        "raises canopy temperature."
    ),
    "cotton": (
        "Waterlogging for more than 48 hours can damage cotton root systems — "
        "prioritize drainage if heavy rain is forecast."
    ),
    "sugarcane": (
        "Tolerant of short waterlogging, but heat stress above 40C during peak "
        "growth can reduce yield — consider irrigation before hot spells."
    ),
}


def get_agriculture_advisory(
    latitude: float, longitude: float, crop: str | None = None, days: int = 5
) -> dict:
    forecast_days = get_forecast(latitude, longitude, days=days)
    alerts = list_alerts(latitude=latitude, longitude=longitude, radius_km=_ALERT_RADIUS_KM)

    advisories: list[str] = []

    very_heavy_rain_days = [d for d in forecast_days if d["precip_sum_mm"] >= _VERY_HEAVY_RAIN_MM]
    heavy_rain_days = [d for d in forecast_days if d["precip_sum_mm"] >= _HEAVY_RAIN_MM]
    if very_heavy_rain_days:
        advisories.append(
            "Very heavy rain forecast (>115.6mm/day) — hold off sowing, fertilizer, and "
            "pesticide application; ensure field drainage is clear."
        )
    elif heavy_rain_days:
        advisories.append(
            "Heavy rain forecast (>64.5mm/day) — avoid irrigation and hold off "
            "fertilizer/pesticide application until after the rain."
        )

    severe_heat_days = [d for d in forecast_days if d["temp_max_c"] >= _SEVERE_HEAT_STRESS_C]
    hot_days = [d for d in forecast_days if d["temp_max_c"] >= _HEAT_STRESS_C]
    if severe_heat_days:
        advisories.append(
            "Severe heat stress forecast (>=45C) — irrigate early morning or evening, "
            "avoid midday fieldwork."
        )
    elif hot_days:
        advisories.append(
            "Heat stress forecast (>=40C) — consider additional irrigation and avoid "
            "applying chemicals during peak afternoon heat."
        )

    frost_days = [d for d in forecast_days if d["temp_min_c"] <= _FROST_RISK_C]
    if frost_days:
        advisories.append(
            "Frost risk forecast (<=4C overnight) — light irrigation the evening before "
            "a cold night can help protect standing crops."
        )

    if not heavy_rain_days and not hot_days and forecast_days:
        dry_spell = all(
            (d["precip_probability_pct"] or 0) < _DRY_SPELL_PRECIP_PROBABILITY_PCT
            for d in forecast_days
        )
        if dry_spell:
            advisories.append(
                "No significant rain expected in the forecast window — plan irrigation "
                "accordingly."
            )

    if crop:
        note = _CROP_NOTES.get(crop.lower())
        if note:
            advisories.append(note)

    relevant_alerts = [
        a for a in alerts if any(keyword in a["event_type"].lower() for keyword in _ALERT_KEYWORDS)
    ]

    return {
        "latitude": latitude,
        "longitude": longitude,
        "crop": crop,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "advisories": advisories,
        "active_alerts": relevant_alerts,
        "forecast_basis": forecast_days,
    }
