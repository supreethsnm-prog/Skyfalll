"""Tool registry for the chat orchestration loop (app/chat/service.py).

Every handler here calls an existing query-path service function — never a
raw provider and never a table directly — so every tool call inherits that
service's caching behavior and its raw_payload exclusion for free. This is
the mechanical enforcement of the spec's grounding principle (section 1):
the LLM can only ever learn a fact through one of these, never invent one.
"""

import json

from app.aviation.service import get_metar
from app.forecast.service import get_forecast
from app.geocoding.service import geocode_place
from app.history.service import get_historical_weather
from app.marine.service import list_pfz_zones
from app.nwp.service import get_nwp_forecast
from app.providers.llm import ToolSpec
from app.skills.agriculture import get_agriculture_advisory
from app.skills.urban import get_urban_advisory
from app.translation.service import translate_text
from app.warning.service import list_alerts
from app.weather.service import get_weather

TOOL_SPECS: list[ToolSpec] = [
    ToolSpec(
        name="get_weather",
        description="Get current weather (temperature, humidity, wind) for a specific latitude/longitude coordinate.",
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
            },
            "required": ["latitude", "longitude"],
        },
    ),
    ToolSpec(
        name="get_forecast",
        description=(
            "Get a multi-day weather forecast (daily high/low temperature, rain "
            "probability, precipitation, wind) for a specific latitude/longitude "
            "coordinate. Use this for questions about tomorrow, upcoming days, or "
            "the weekly forecast — get_weather only covers right now."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
                "days": {
                    "type": "integer",
                    "description": "Number of days to forecast (1-16, default 5)",
                },
            },
            "required": ["latitude", "longitude"],
        },
    ),
    ToolSpec(
        name="geocode",
        description="Look up the coordinates and display name for a place name (city, district, landmark).",
        input_schema={
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "A place name, e.g. 'Mumbai, India'"},
            },
            "required": ["query"],
        },
    ),
    ToolSpec(
        name="get_metar",
        description="Get the current aviation weather observation (METAR) for an airport by its 4-letter ICAO code.",
        input_schema={
            "type": "object",
            "properties": {
                "icao": {"type": "string", "description": "4-letter ICAO airport code, e.g. VABB"},
            },
            "required": ["icao"],
        },
    ),
    ToolSpec(
        name="list_alerts",
        description=(
            "List currently active disaster/weather alerts and warnings across India. "
            "Pass latitude and longitude to filter to alerts within 100km of a specific "
            "location; omit both to get all alerts nationwide."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
            },
        },
    ),
    ToolSpec(
        name="list_pfz_zones",
        description=(
            "List currently advised marine Potential Fishing Zones (PFZ). Pass latitude "
            "and longitude to filter to zones within 200km of a specific coastal location; "
            "omit both to get all zones nationwide."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
            },
        },
    ),
    ToolSpec(
        name="agriculture_advisory",
        description=(
            "Get a rules-based farming advisory (irrigation, heat-stress, frost, and "
            "heavy-rain guidance) for a specific latitude/longitude coordinate, based on "
            "the forecast and any active weather alerts nearby. Optionally pass a crop "
            "name (e.g. 'rice', 'wheat', 'cotton', 'sugarcane') for a crop-specific note."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
                "crop": {"type": "string", "description": "Optional crop name, e.g. 'rice'"},
            },
            "required": ["latitude", "longitude"],
        },
    ),
    ToolSpec(
        name="urban_advisory",
        description=(
            "Get a rules-based urban-planning advisory (waterlogging, heat, and wind risk) "
            "for a specific latitude/longitude coordinate, based on the forecast and any "
            "active weather alerts nearby."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
            },
            "required": ["latitude", "longitude"],
        },
    ),
    ToolSpec(
        name="get_nwp_forecast",
        description=(
            "Get a medium-range (up to 5-day-ahead) weather outlook from the GFS global "
            "numerical model — temperature, humidity, wind, precipitation rate, cloud cover, "
            "CAPE/CIN, and sea-level pressure at 0/24/48/72/96/120 hours ahead. Complements "
            "get_forecast (Open-Meteo, near-term) with a second, independent "
            "government-model-based source. Only covers India (6-38N, 68-98E)."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "latitude": {"type": "number", "description": "Latitude in decimal degrees"},
                "longitude": {"type": "number", "description": "Longitude in decimal degrees"},
            },
            "required": ["latitude", "longitude"],
        },
    ),
    ToolSpec(
        name="translate_text",
        description=(
            "Translate an exact string deterministically via Bhashini NMT "
            "(IndicTrans2, 22 scheduled languages + English). Use for alerts, "
            "advisories, or UI labels where numbers/units must not drift. "
            "Free-form conversation stays on the LLM — this is for literal "
            "translation only. ISO-639 codes, e.g. source 'en', target 'hi'."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Text to translate, e.g. 'Heavy rainfall expected'"},
                "source": {"type": "string", "description": "Source ISO-639 code, e.g. 'en'"},
                "target": {"type": "string", "description": "Target ISO-639 code, e.g. 'hi'"},
            },
            "required": ["text", "source", "target"],
        },
    ),
    ToolSpec(
        name="get_historical_weather",
        description=(
            "Get historical weather (temperature, precipitation, wind, pressure) for a "
            "specific major Indian city on a specific past date, from ERA5 reanalysis data. "
            "Each reading is a single 12:00 UTC (17:30 IST) snapshot for that date, not a "
            "daily mean/max or a 24-hour precipitation total. precip_mm specifically is the "
            "1-hour accumulation ending at the observation time (12:00 UTC / 17:30 IST), not "
            "a daily total — a very low or zero value does not mean the whole day was dry. "
            "IMPORTANT: this only covers a "
            "small, fixed, pre-seeded set of cities and sample dates (not arbitrary "
            "locations/dates) — if this tool returns not-found, tell the user this specific "
            "city/date combination isn't in the pre-loaded historical dataset, don't imply "
            "historical data doesn't exist at all."
        ),
        input_schema={
            "type": "object",
            "properties": {
                "location": {"type": "string", "description": "A city name, e.g. 'Mumbai'"},
                "date": {"type": "string", "description": "Date in 'YYYY-MM-DD' format"},
            },
            "required": ["location", "date"],
        },
    ),
]


def _handle_get_weather(tool_input: dict) -> dict:
    return get_weather(latitude=tool_input["latitude"], longitude=tool_input["longitude"])


def _handle_get_forecast(tool_input: dict) -> list[dict]:
    days = tool_input.get("days", 5)
    return get_forecast(
        latitude=tool_input["latitude"], longitude=tool_input["longitude"], days=days
    )


def _handle_geocode(tool_input: dict) -> dict:
    result = geocode_place(tool_input["query"])
    if result is None:
        return {"error": f"No location found for '{tool_input['query']}'"}
    return result


def _handle_get_metar(tool_input: dict) -> dict:
    result = get_metar(tool_input["icao"])
    if result is None:
        return {"error": f"No current METAR observation for '{tool_input['icao']}'"}
    return result


_CHAT_TOOL_RESULT_CAP = 20


def _handle_list_alerts(tool_input: dict) -> list[dict]:
    # Chat-context size limit, not a data-correctness truncation: the real
    # /alerts endpoint (app/main.py) returns the full, unfiltered list.
    results = list_alerts(
        latitude=tool_input.get("latitude"), longitude=tool_input.get("longitude")
    )
    return results[:_CHAT_TOOL_RESULT_CAP]


def _handle_list_pfz_zones(tool_input: dict) -> list[dict]:
    # Chat-context size limit (cap) plus geometry stripping: the LLM doesn't
    # need raw coordinate geometry to answer a conversational question about
    # which zones are active, and the full MultiLineString arrays risk
    # crowding out max_tokens. The real /marine/pfz-zones endpoint (app/main.py)
    # deliberately keeps geometry — this only affects the chat tool handler.
    zones = list_pfz_zones(
        latitude=tool_input.get("latitude"), longitude=tool_input.get("longitude")
    )[:_CHAT_TOOL_RESULT_CAP]
    return [{k: v for k, v in zone.items() if k != "geometry"} for zone in zones]


def _handle_agriculture_advisory(tool_input: dict) -> dict:
    return get_agriculture_advisory(
        latitude=tool_input["latitude"],
        longitude=tool_input["longitude"],
        crop=tool_input.get("crop"),
    )


def _handle_urban_advisory(tool_input: dict) -> dict:
    return get_urban_advisory(latitude=tool_input["latitude"], longitude=tool_input["longitude"])


def _handle_get_nwp_forecast(tool_input: dict) -> list[dict]:
    return get_nwp_forecast(latitude=tool_input["latitude"], longitude=tool_input["longitude"])


def _handle_translate_text(tool_input: dict) -> dict:
    return translate_text(
        text=tool_input["text"],
        source_language=tool_input["source"],
        target_language=tool_input["target"],
    )


def _handle_get_historical_weather(tool_input: dict) -> dict:
    result = get_historical_weather(tool_input["location"], tool_input["date"])
    if result is None:
        return {
            "error": (
                f"No historical data for '{tool_input['location']}' on "
                f"{tool_input['date']}"
            )
        }
    return result


_HANDLERS = {
    "get_weather": _handle_get_weather,
    "get_forecast": _handle_get_forecast,
    "geocode": _handle_geocode,
    "get_metar": _handle_get_metar,
    "list_alerts": _handle_list_alerts,
    "list_pfz_zones": _handle_list_pfz_zones,
    "agriculture_advisory": _handle_agriculture_advisory,
    "urban_advisory": _handle_urban_advisory,
    "get_nwp_forecast": _handle_get_nwp_forecast,
    "translate_text": _handle_translate_text,
    "get_historical_weather": _handle_get_historical_weather,
}


def execute_tool(name: str, tool_input: dict) -> str:
    handler = _HANDLERS.get(name)
    if handler is None:
        return json.dumps({"error": f"Unknown tool '{name}'"})
    try:
        result = handler(tool_input)
        return json.dumps(result, default=str)
    except Exception as exc:
        return json.dumps({"error": f"Tool '{name}' failed: {exc}"})
