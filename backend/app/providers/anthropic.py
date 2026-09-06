"""Anthropic Messages API adapter for the LLMProvider abstraction.

Unlike every provider elsewhere in this codebase, this one is never
wrapped in a caching layer (see app/chat/service.py's module docstring
for why) — every call this provider makes is live, on every chat turn.
"""

import httpx

from app.config import get_settings
from app.providers.llm import LLMTurn, ToolCall, ToolSpec

ANTHROPIC_BASE_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"


def _translate_history(history: list[dict]) -> list[dict]:
    wire_messages: list[dict] = []
    for entry in history:
        role = entry["role"]
        if role == "user":
            wire_messages.append({"role": "user", "content": entry["content"]})
        elif role == "assistant":
            tool_calls = entry.get("tool_calls") or []
            if not tool_calls:
                wire_messages.append({"role": "assistant", "content": entry.get("content") or ""})
                continue
            content_blocks = []
            if entry.get("content"):
                content_blocks.append({"type": "text", "text": entry["content"]})
            for call in tool_calls:
                content_blocks.append(
                    {
                        "type": "tool_use",
                        "id": call["id"],
                        "name": call["name"],
                        "input": call["input"],
                    }
                )
            wire_messages.append({"role": "assistant", "content": content_blocks})
        elif role == "tool":
            result_block = {
                "type": "tool_result",
                "tool_use_id": entry["tool_call_id"],
                "content": entry["content"],
            }
            if wire_messages and wire_messages[-1]["role"] == "user" and isinstance(
                wire_messages[-1]["content"], list
            ):
                wire_messages[-1]["content"].append(result_block)
            else:
                wire_messages.append({"role": "user", "content": [result_block]})
        else:
            raise ValueError(f"Unknown history role: {role!r}")
    return wire_messages


def _translate_tools(tools: list[ToolSpec]) -> list[dict]:
    return [
        {"name": tool.name, "description": tool.description, "input_schema": tool.input_schema}
        for tool in tools
    ]


class AnthropicLLMProvider:
    def __init__(
        self,
        api_key: str | None = None,
        model: str | None = None,
        base_url: str = ANTHROPIC_BASE_URL,
        client: httpx.Client | None = None,
    ):
        settings = get_settings()
        self._api_key = api_key if api_key is not None else settings.anthropic_api_key
        if not self._api_key:
            raise ValueError(
                "ANTHROPIC_API_KEY is not set. Set it in backend/.env or as an "
                "environment variable to enable chat."
            )
        self._model = model or settings.anthropic_model
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=30.0)

    def generate(self, system: str, history: list[dict], tools: list[ToolSpec]) -> LLMTurn:
        try:
            response = self._client.post(
                self._base_url,
                headers={
                    "x-api-key": self._api_key,
                    "anthropic-version": ANTHROPIC_VERSION,
                    "content-type": "application/json",
                },
                json={
                    "model": self._model,
                    "max_tokens": 1024,
                    "system": system,
                    "messages": _translate_history(history),
                    "tools": _translate_tools(tools),
                },
            )
            response.raise_for_status()
            payload = response.json()

            text_parts = []
            tool_calls = []
            for block in payload.get("content", []):
                if block["type"] == "text":
                    text_parts.append(block["text"])
                elif block["type"] == "tool_use":
                    tool_calls.append(
                        ToolCall(id=block["id"], name=block["name"], input=block["input"])
                    )

            return LLMTurn(
                text="".join(text_parts) or None,
                tool_calls=tool_calls,
                stop_reason=payload.get("stop_reason", "end_turn"),
            )
        finally:
            if self._owns_client:
                self._client.close()
