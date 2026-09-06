"""Tool registry for the chat orchestration loop (app/chat/service.py).

Every handler here calls an existing query-path service function — never a
raw provider and never a table directly — so every tool call inherits that
service's caching behavior and its raw_payload exclusion for free. This is
the mechanical enforcement of the spec's grounding principle (section 1):
the LLM can only ever learn a fact through one of these, never invent one.
"""

import json

from app.aviation.service import get_metar
from app.geocoding.service import geocode_place
from app.marine.service import list_pfz_zones
from app.providers.llm import ToolSpec
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
        description="List all currently active disaster/weather alerts and warnings across India.",
        input_schema={"type": "object", "properties": {}},
    ),
    ToolSpec(
        name="list_pfz_zones",
        description="List all currently advised marine Potential Fishing Zones (PFZ).",
        input_schema={"type": "object", "properties": {}},
    ),
]


def _handle_get_weather(tool_input: dict) -> dict:
    return get_weather(latitude=tool_input["latitude"], longitude=tool_input["longitude"])


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
    # /alerts endpoint (app/main.py) returns the full list.
    return list_alerts()[:_CHAT_TOOL_RESULT_CAP]


def _handle_list_pfz_zones(tool_input: dict) -> list[dict]:
    # Chat-context size limit (cap) plus geometry stripping: the LLM doesn't
    # need raw coordinate geometry to answer a conversational question about
    # which zones are active, and the full MultiLineString arrays risk
    # crowding out max_tokens. The real /marine/pfz-zones endpoint (app/main.py)
    # deliberately keeps geometry — this only affects the chat tool handler.
    zones = list_pfz_zones()[:_CHAT_TOOL_RESULT_CAP]
    return [{k: v for k, v in zone.items() if k != "geometry"} for zone in zones]


_HANDLERS = {
    "get_weather": _handle_get_weather,
    "geocode": _handle_geocode,
    "get_metar": _handle_get_metar,
    "list_alerts": _handle_list_alerts,
    "list_pfz_zones": _handle_list_pfz_zones,
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
