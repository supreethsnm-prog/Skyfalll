"""Agentic tool-calling loop for the conversational chat endpoint.

This is a fourth query-path pattern, distinct from the three caching
patterns elsewhere in this codebase (scheduled-ingestion — see
app/ingestion/alerts.py; cache-with-TTL — see app/weather/service.py;
permanent-cache — see app/geocoding/service.py): a chat reply is never
cached. Each turn is a fresh generation, since a conversational response
is inherently non-idempotent — the same question asked twice can get a
differently-phrased (and, if history differs, differently-grounded)
answer. Caching would risk serving a stale or context-mismatched reply.

The LLM only ever learns facts through app/chat/tools.py's registry,
which reads exclusively from the existing query-path services — never
directly from a provider or a raw table — per the spec's grounding
principle (WeatherGPT V1 design doc, section 1).
"""

import logging
import time

from app.chat.tools import TOOL_SPECS, execute_tool
from app.providers.factory import build_llm_provider
from app.providers.llm import LLMProvider

logger = logging.getLogger(__name__)

_MAX_TOOL_ITERATIONS = 5

# A generous ceiling on total time this function can spend across every
# generate()/tool-execution round in one request, even if _MAX_TOOL_ITERATIONS
# hasn't been reached yet — bounds the worst case where retry.py's own
# per-call backoff (up to ~95s per generate() call, see app/providers/retry.py)
# would otherwise compose with this loop's iteration count into a multi-minute
# hang instead of a fast, clear failure.
_CHAT_TURN_DEADLINE_SECONDS = 60.0

_SYSTEM_PROMPT = (
    "You are WeatherGPT, a conversational assistant for weather, marine, "
    "aviation, and disaster-alert information in India. Always use the "
    "provided tools to look up current facts — never state a specific "
    "weather value, alert, or observation from memory. If a tool reports "
    "an error or no data, say so plainly rather than guessing. If a "
    "question has multiple parts (e.g. both a forecast and an alert "
    "check), call every tool needed to answer all of them — never silently "
    "skip part of a question because it seemed less important.\n\n"
    "get_weather, get_forecast, list_alerts, and list_pfz_zones all accept "
    "coordinates, not place names. When the user names a place, call "
    "geocode first to resolve it, then pass the coordinates it returns to "
    "whichever of those tools you need. Use get_weather for right-now "
    "conditions and get_forecast for tomorrow, upcoming days, or a weekly "
    "outlook — they are not interchangeable.\n\n"
    "For farming or crop-related questions, use agriculture_advisory; for "
    "city-planning, waterlogging, or heat-risk questions, use urban_advisory. "
    "Both take coordinates, not place names — geocode first if the user named "
    "a place.\n\n"
    "get_nwp_forecast gives a medium-range (up to 5-day-ahead) outlook from the "
    "GFS government numerical model, covering India only — use it when the user "
    "wants a longer-horizon or second-opinion outlook, or explicitly asks about "
    "GFS/model data, CAPE/CIN, or sea-level pressure. Use get_forecast (Open-Meteo) "
    "for ordinary near-term day-by-day questions; they are independent sources and "
    "can be combined when the user wants both perspectives.\n\n"
    "Reply in the same language the user wrote in — including Hindi, Telugu, "
    "Tamil, Bengali, Marathi and other Indian languages — keeping numbers, "
    "units and place names in standard form."
)


def chat_turn(
    message: str,
    history: list[dict] | None = None,
    provider: LLMProvider | None = None,
) -> dict:
    # chat_turn owns the lifecycle of a provider it constructs itself (no
    # provider argument given), and closes it once the loop is done. An
    # injected provider (e.g. a test double, or a caller with a longer-lived
    # instance such as the /chat endpoint's Depends-provided one) is never
    # closed here — its lifecycle belongs to whoever constructed it.
    owns_llm = provider is None
    llm = provider or build_llm_provider()
    try:
        conversation = list(history or [])
        conversation.append({"role": "user", "content": message})
        start_time = time.monotonic()

        for _ in range(_MAX_TOOL_ITERATIONS):
            if time.monotonic() - start_time > _CHAT_TURN_DEADLINE_SECONDS:
                logger.warning(
                    "Chat turn exceeded its %.0fs deadline before reaching a final answer",
                    _CHAT_TURN_DEADLINE_SECONDS,
                )
                fallback_reply = (
                    "That's taking longer than expected — please try again in a moment."
                )
                conversation.append({"role": "assistant", "content": fallback_reply})
                return {"reply": fallback_reply, "history": conversation}

            turn = llm.generate(system=_SYSTEM_PROMPT, history=conversation, tools=TOOL_SPECS)

            if turn.stop_reason == "max_tokens":
                logger.warning("LLM response truncated (stop_reason=max_tokens)")

            if turn.tool_calls:
                conversation.append(
                    {
                        "role": "assistant",
                        "content": turn.text or "",
                        "tool_calls": [
                            {"id": call.id, "name": call.name, "input": call.input}
                            for call in turn.tool_calls
                        ],
                    }
                )
                for call in turn.tool_calls:
                    result = execute_tool(call.name, call.input)
                    conversation.append(
                        {
                            "role": "tool",
                            "tool_call_id": call.id,
                            # Gemini matches a result to its call by name, not id.
                            "name": call.name,
                            "content": result,
                        }
                    )
                continue

            conversation.append({"role": "assistant", "content": turn.text or ""})
            return {"reply": turn.text or "", "history": conversation}

        logger.warning(
            "Chat turn hit max tool-call iterations (%d) without a final answer",
            _MAX_TOOL_ITERATIONS,
        )
        fallback_reply = (
            "I wasn't able to finish looking that up — please try rephrasing your question."
        )
        conversation.append({"role": "assistant", "content": fallback_reply})
        return {"reply": fallback_reply, "history": conversation}
    finally:
        if owns_llm:
            llm.close()
