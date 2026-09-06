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

from app.chat.tools import TOOL_SPECS, execute_tool
from app.providers.anthropic import AnthropicLLMProvider
from app.providers.llm import LLMProvider

logger = logging.getLogger(__name__)

_MAX_TOOL_ITERATIONS = 5

_SYSTEM_PROMPT = (
    "You are WeatherGPT, a conversational assistant for weather, marine, "
    "aviation, and disaster-alert information in India. Always use the "
    "provided tools to look up current facts — never state a specific "
    "weather value, alert, or observation from memory. If a tool reports "
    "an error or no data, say so plainly rather than guessing.\n\n"
    "get_weather takes coordinates, not place names. When the user names a "
    "place, call geocode first to resolve it, then pass the coordinates it "
    "returns to get_weather.\n\n"
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
    llm = provider or AnthropicLLMProvider()
    try:
        conversation = list(history or [])
        conversation.append({"role": "user", "content": message})

        for _ in range(_MAX_TOOL_ITERATIONS):
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
                        {"role": "tool", "tool_call_id": call.id, "content": result}
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
