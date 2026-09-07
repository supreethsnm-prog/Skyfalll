"""Google Gemini (generativelanguage) adapter for the LLMProvider abstraction.

Gemini's wire format differs from Anthropic's in ways that all live in this
file, which is the point of the LLMProvider Protocol:
  - the assistant role is called "model"
  - tool schemas are `functionDeclarations` with `parameters`, not `input_schema`
  - function calls carry NO id; a result is matched to its call by NAME
  - when one turn calls the SAME tool more than once (Gemini has no id to
    tell such calls apart), disambiguation relies entirely on returning
    functionResponse parts in the same order the functionCall parts
    arrived in — verified against the real API (see
    docs/superpowers/plans/2026-09-07-gemini-followups.md for the live
    transcript), but not a behavior Google's API docs formally guarantee.
    _translate_history must never reorder tool-role history entries
    relative to their append order.
  - `finishReason` is "STOP" even when the model emitted a function call, so
    tool use is detected by the presence of functionCall parts
  - `functionResponse.response` must be a JSON object, never a bare list

Like app/providers/anthropic.py, this provider is never wrapped in a cache —
see app/chat/service.py's module docstring.
"""

import itertools
import json

import httpx

from app.config import get_settings
from app.providers.llm import LLMTurn, ToolCall, ToolSpec

GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"


def _as_response_object(content: str) -> dict:
    """Gemini requires functionResponse.response to be a JSON object.

    execute_tool returns a JSON string that may encode a list (list_alerts,
    list_pfz_zones) or a scalar, so anything that isn't already an object is
    wrapped rather than sent as-is.
    """
    try:
        parsed = json.loads(content)
    except (TypeError, ValueError):
        return {"result": content}
    if isinstance(parsed, dict):
        return parsed
    return {"result": parsed}


def _translate_history(history: list[dict]) -> list[dict]:
    contents: list[dict] = []
    # Gemini matches a tool result to its call by name, so remember the name
    # each call id was issued under for histories that omit it.
    id_to_name: dict[str, str] = {}

    for entry in history:
        role = entry["role"]
        if role == "user":
            contents.append({"role": "user", "parts": [{"text": entry["content"]}]})
        elif role == "assistant":
            parts: list[dict] = []
            if entry.get("content"):
                parts.append({"text": entry["content"]})
            for call in entry.get("tool_calls") or []:
                id_to_name[call["id"]] = call["name"]
                parts.append({"functionCall": {"name": call["name"], "args": call["input"]}})
            if not parts:
                parts.append({"text": ""})
            contents.append({"role": "model", "parts": parts})
        elif role == "tool":
            name = entry.get("name") or id_to_name.get(entry.get("tool_call_id", ""))
            if not name:
                raise ValueError(
                    f"Cannot resolve a function name for tool result "
                    f"{entry.get('tool_call_id')!r} — no 'name' on the entry and no "
                    f"matching tool call earlier in the history."
                )
            part = {
                "functionResponse": {
                    "name": name,
                    "response": _as_response_object(entry["content"]),
                }
            }
            if (
                contents
                and contents[-1]["role"] == "user"
                and any("functionResponse" in p for p in contents[-1]["parts"])
            ):
                contents[-1]["parts"].append(part)
            else:
                contents.append({"role": "user", "parts": [part]})
        else:
            raise ValueError(f"Unknown history role: {role!r}")
    return contents


def _translate_tools(tools: list[ToolSpec]) -> list[dict]:
    return [
        {
            "functionDeclarations": [
                {
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.input_schema,
                }
                for tool in tools
            ]
        }
    ]


_call_id_counter = itertools.count()


class GeminiLLMProvider:
    def __init__(
        self,
        api_key: str | None = None,
        model: str | None = None,
        base_url: str = GEMINI_BASE_URL,
        client: httpx.Client | None = None,
    ):
        settings = get_settings()
        self._api_key = api_key if api_key is not None else settings.gemini_api_key
        if not self._api_key:
            raise ValueError(
                "GEMINI_API_KEY is not set. Set it in backend/.env or as an "
                "environment variable to enable chat."
            )
        self._model = model or settings.gemini_model
        self._max_tokens = settings.gemini_max_tokens
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=30.0)

    def generate(self, system: str, history: list[dict], tools: list[ToolSpec]) -> LLMTurn:
        body: dict = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": _translate_history(history),
            "generationConfig": {"maxOutputTokens": self._max_tokens},
        }
        if tools:
            body["tools"] = _translate_tools(tools)

        response = self._client.post(
            f"{self._base_url}/models/{self._model}:generateContent",
            headers={
                # Header auth, never a ?key= query param: secrets must not
                # appear in URLs, where they leak into logs and proxies.
                "x-goog-api-key": self._api_key,
                "content-type": "application/json",
            },
            json=body,
        )
        response.raise_for_status()
        payload = response.json()

        candidates = payload.get("candidates") or []
        if not candidates:
            return LLMTurn(text=None, tool_calls=[], stop_reason="end_turn")

        candidate = candidates[0]
        parts = (candidate.get("content") or {}).get("parts") or []

        text_parts: list[str] = []
        tool_calls: list[ToolCall] = []
        for part in parts:
            if "text" in part:
                text_parts.append(part["text"])
            elif "functionCall" in part:
                function_call = part["functionCall"]
                tool_calls.append(
                    ToolCall(
                        # Gemini supplies no call id. Synthesized ids must be
                        # unique for the life of the process, not just within
                        # one generate() call — an index-based id would repeat
                        # across a conversation's rounds (round 1 and round 2
                        # could both mint "gemini-0"), which is harmless today
                        # (the server always attaches "name" to tool-role
                        # history entries, so this id is never looked up) but
                        # is a trap for any future code that correlates by id
                        # across a whole conversation.
                        id=f"gemini-{next(_call_id_counter)}",
                        name=function_call["name"],
                        input=function_call.get("args") or {},
                    )
                )

        if tool_calls:
            stop_reason = "tool_use"
        elif candidate.get("finishReason") == "MAX_TOKENS":
            stop_reason = "max_tokens"
        else:
            stop_reason = "end_turn"

        return LLMTurn(
            text="".join(text_parts) or None,
            tool_calls=tool_calls,
            stop_reason=stop_reason,
        )

    def close(self) -> None:
        """Close the underlying HTTP client, but only if this provider created it.

        Never call this from generate(): chat_turn calls generate() repeatedly
        on one instance whenever the model requests a tool.
        """
        if self._owns_client:
            self._client.close()
