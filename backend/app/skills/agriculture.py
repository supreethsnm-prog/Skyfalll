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

# Practical/operational choice, not an IMD-published classification: a
# forecast window where every day sits below this rain probability is treated
# as "no useful rain to plan around" for irrigation purposes.
_DRY_SPELL_PRECIP_PROBABILITY_PCT = 20.0

# Companion guard to the probability check above, also a practical choice (not
# IMD-cited): precip_probability_pct is nullable, so a day only counts toward a
# dry spell if its actual forecast rainfall is negligible too — a day with real
# rain must never read as "definitely dry" just because probability was absent.
_DRY_SPELL_MAX_PRECIP_MM = 5.0

# Operational choice, not an IMD figure: deliberately tighter than
# ``list_alerts``' own default radius_km=100.0 (see app/warning/service.py)
# because a farm-scale advisory reasonably cares about a smaller neighbourhood
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

# Illustrative, non-exhaustive crop-specific notes — not authoritative
# agronomic guidance, only a starting point for the advisory text. Keyed by
# crop, then by the advisory trigger the note actually applies to, so a note is
# only ever emitted alongside the rule that makes it relevant.
_CROP_NOTES = {
    "rice": {
        "heavy_rain": (
            "Standing water is tolerated, but ensure field drainage if heavy rain is "
            "forecast to prevent root rot."
        ),
    },
    "wheat": {
        "frost": (
            "Frost below 4C can damage standing wheat during flowering/grain-filling — "
            "consider light irrigation the evening before a forecast cold night, which "
            "raises canopy temperature."
        ),
    },
    "cotton": {
        "heavy_rain": (
            "Waterlogging for more than 48 hours can damage cotton root systems — "
            "prioritize drainage if heavy rain is forecast."
        ),
    },
    "sugarcane": {
        "heat_stress": (
            "Tolerant of short waterlogging, but heat stress above 40C during peak "
            "growth can reduce yield — consider irrigation before hot spells."
        ),
    },
}


def _is_relevant_alert(alert: dict) -> bool:
    event_type = (alert.get("event_type") or "").lower()
    if not event_type:
        # Can't classify — err toward inclusion for a safety-relevant filter
        # rather than silently dropping an alert we can't categorize.
        return True
    return any(keyword in event_type for keyword in _ALERT_KEYWORDS)


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
            "Very heavy rain forecast (>=115.6mm/day) — hold off sowing, fertilizer, and "
            "pesticide application; ensure field drainage is clear."
        )
    elif heavy_rain_days:
        advisories.append(
            "Heavy rain forecast (>=64.5mm/day) — avoid irrigation and hold off "
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
        # precip_probability_pct is nullable, so the rainfall total is checked
        # alongside it: a null probability must not read as "definitely dry"
        # on a day whose precip_sum_mm shows real rain.
        dry_spell = all(
            (d["precip_probability_pct"] or 0) < _DRY_SPELL_PRECIP_PROBABILITY_PCT
            and (d["precip_sum_mm"] or 0) < _DRY_SPELL_MAX_PRECIP_MM
            for d in forecast_days
        )
        if dry_spell:
            advisories.append(
                "No significant rain expected in the forecast window — plan irrigation "
                "accordingly."
            )

    # A crop note is only relevant alongside the rule that makes it relevant —
    # appending every note for a matched crop produced advice contradicting the
    # forecast (e.g. a drainage note during a bone-dry heatwave).
    fired: set[str] = set()
    if very_heavy_rain_days or heavy_rain_days:
        fired.add("heavy_rain")
    if severe_heat_days or hot_days:
        fired.add("heat_stress")
    if frost_days:
        fired.add("frost")

    if crop:
        crop_notes = _CROP_NOTES.get(crop.lower(), {})
        for trigger in sorted(fired):
            note = crop_notes.get(trigger)
            if note:
                advisories.append(note)

    relevant_alerts = [a for a in alerts if _is_relevant_alert(a)]
    if relevant_alerts:
        advisories.append(
            f"{len(relevant_alerts)} active weather alert(s) within "
            f"{_ALERT_RADIUS_KM:.0f}km — see active_alerts for details."
        )

    return {
        "latitude": latitude,
        "longitude": longitude,
        "crop": crop,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "advisories": advisories,
        "active_alerts": relevant_alerts,
        "forecast_basis": forecast_days,
    }
