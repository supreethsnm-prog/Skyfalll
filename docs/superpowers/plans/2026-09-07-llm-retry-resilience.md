# LLM Call Retry and Error Classification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Right now, if Anthropic or Gemini returns a transient failure (a 429 rate limit, a 503, a dropped connection) during a chat turn, the request dies immediately with no retry — in a live demo, one API hiccup ends the conversation. Separately, a malformed/unparseable response from the LLM vendor is currently misclassified as "invalid user history" (422) because `json.JSONDecodeError` is a `ValueError` subclass and gets caught by the same except clause that handles genuinely bad client input. This plan adds jittered exponential backoff for transient failures and fixes the error classification so each failure mode gets an honest, distinct HTTP status.

**Architecture:** One shared retry helper (`app/providers/retry.py`) wraps the outbound HTTP call inside both `AnthropicLLMProvider.generate()` and `GeminiLLMProvider.generate()` — the retry logic is vendor-agnostic (it operates on the `httpx.Response`/exception, not on either vendor's wire format), so it lives once and both adapters use it, the same way `app/geo.py`'s `haversine_km` is shared by two otherwise-independent services.

**Tech Stack:** Same as the rest of the backend — httpx, no new dependency.

**Spec:** docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md (no spec changes — this is a reliability hardening of the already-spec-compliant chat layer, not new scope).

## Current state (read to confirm before editing)

`app/providers/anthropic.py`'s `generate()`:
```python
    def generate(self, system: str, history: list[dict], tools: list[ToolSpec]) -> LLMTurn:
        response = self._client.post(
            self._base_url,
            headers={
                "x-api-key": self._api_key,
                "anthropic-version": ANTHROPIC_VERSION,
                "content-type": "application/json",
            },
            json={
                "model": self._model,
                "max_tokens": self._max_tokens,
                "system": system,
                "messages": _translate_history(history),
                "tools": _translate_tools(tools),
            },
        )
        response.raise_for_status()
        payload = response.json()
        ...
```

`app/providers/gemini.py`'s `generate()` (relevant excerpt):
```python
        response = self._client.post(
            f"{self._base_url}/models/{self._model}:generateContent",
            headers={
                "x-goog-api-key": self._api_key,
                "content-type": "application/json",
            },
            json=body,
        )
        response.raise_for_status()
        payload = response.json()
        ...
```

`app/main.py`'s `chat_endpoint`:
```python
def chat_endpoint(
    request: ChatRequest, llm: LLMProvider = Depends(get_llm_provider)
) -> dict:
    try:
        return chat_turn(request.message, request.history, provider=llm)
    except (KeyError, ValueError) as e:
        raise HTTPException(status_code=422, detail=f"Invalid history: {e}") from e
```

`json.JSONDecodeError` is a subclass of `ValueError` — a malformed response body from either LLM vendor (not malformed client history) currently gets caught by this same clause and reported to the client as "Invalid history," which is wrong and misleading for debugging.

## Global Constraints

- Only retry failures that are actually transient: a specific set of HTTP status codes (429, 500, 502, 503, 504) and network-level errors (connection failures, timeouts) — never a 4xx client error like 400/401/403/404, where an identical retry cannot succeed.
- Retry delay uses jittered exponential backoff, and honors a vendor's `Retry-After` header when present (Anthropic sends this on rate-limit responses).
- Tests must never sleep real time — the retry helper's delay must be patchable via `monkeypatch.setattr` on the module's `time.sleep` reference, not a function-default-bound reference (default arguments are evaluated once at function-definition time, so `def f(sleep=time.sleep)` captures the function object permanently and a later `monkeypatch.setattr(time, "sleep", ...)` would NOT affect it — the retry helper must call `time.sleep(...)` directly in its body, referencing the module, so `monkeypatch.setattr("app.providers.retry.time.sleep", ...)` actually takes effect).
- No new dependency — plain `httpx` exception types and the standard library `time`/`random` modules only.

---

### Task 1: Shared retry-with-backoff helper

**Files:**
- Create: `backend/app/providers/retry.py`
- Test: `backend/tests/test_retry.py`

**Interfaces:**
- Produces: `call_with_retries(make_request: Callable[[], httpx.Response], max_attempts: int = 3, base_delay_seconds: float = 1.0) -> httpx.Response`, consumed by Task 2.

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_retry.py`:

```python
import httpx
import pytest

from app.providers.retry import call_with_retries


def _counting_handler(responses):
    """Returns a handler that yields each response in `responses` in order,
    one per call, repeating the last one if called more times than provided."""
    calls = {"count": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        index = min(calls["count"], len(responses) - 1)
        calls["count"] += 1
        response = responses[index]
        if isinstance(response, Exception):
            raise response
        return response

    return handler, calls


def test_succeeds_immediately_with_no_retry_needed(monkeypatch):
    handler, calls = _counting_handler([httpx.Response(200, json={"ok": True})])
    client = httpx.Client(transport=httpx.MockTransport(handler))

    response = call_with_retries(lambda: client.get("http://test/"))

    assert response.status_code == 200
    assert calls["count"] == 1


def test_retries_on_retryable_status_then_succeeds(monkeypatch):
    slept = []
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: slept.append(s))

    handler, calls = _counting_handler(
        [httpx.Response(503), httpx.Response(503), httpx.Response(200, json={"ok": True})]
    )
    client = httpx.Client(transport=httpx.MockTransport(handler))

    response = call_with_retries(lambda: client.get("http://test/"))

    assert response.status_code == 200
    assert calls["count"] == 3
    assert len(slept) == 2  # slept before the 2nd and 3rd attempts


def test_retries_on_429_rate_limit(monkeypatch):
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: None)
    handler, calls = _counting_handler([httpx.Response(429), httpx.Response(200, json={"ok": True})])
    client = httpx.Client(transport=httpx.MockTransport(handler))

    response = call_with_retries(lambda: client.get("http://test/"))

    assert response.status_code == 200
    assert calls["count"] == 2


def test_retries_on_connection_error_then_succeeds(monkeypatch):
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: None)
    handler, calls = _counting_handler(
        [httpx.ConnectError("connection refused"), httpx.Response(200, json={"ok": True})]
    )
    client = httpx.Client(transport=httpx.MockTransport(handler))

    response = call_with_retries(lambda: client.get("http://test/"))

    assert response.status_code == 200
    assert calls["count"] == 2


def test_does_not_retry_non_retryable_client_error(monkeypatch):
    slept = []
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: slept.append(s))
    handler, calls = _counting_handler([httpx.Response(401), httpx.Response(200, json={"ok": True})])
    client = httpx.Client(transport=httpx.MockTransport(handler))

    with pytest.raises(httpx.HTTPStatusError):
        call_with_retries(lambda: client.get("http://test/"))

    # Failed on the first attempt, never touched the second (retryable-looking)
    # response, and never slept.
    assert calls["count"] == 1
    assert slept == []


def test_raises_after_exhausting_max_attempts(monkeypatch):
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: None)
    handler, calls = _counting_handler([httpx.Response(503)])  # always 503

    client = httpx.Client(transport=httpx.MockTransport(handler))

    with pytest.raises(httpx.HTTPStatusError):
        call_with_retries(lambda: client.get("http://test/"), max_attempts=3)

    assert calls["count"] == 3


def test_honors_retry_after_header(monkeypatch):
    delays = []
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: delays.append(s))
    handler, calls = _counting_handler(
        [httpx.Response(429, headers={"retry-after": "5"}), httpx.Response(200, json={"ok": True})]
    )
    client = httpx.Client(transport=httpx.MockTransport(handler))

    call_with_retries(lambda: client.get("http://test/"), base_delay_seconds=0.1)

    assert delays[0] >= 5.0
```

- [ ] **Step 2: Run them, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_retry.py -v`
Expected: FAIL — `app.providers.retry` does not exist.

- [ ] **Step 3: Write `app/providers/retry.py`**

```python
"""Shared retry-with-backoff helper for outbound calls to LLM vendor APIs.

Both AnthropicLLMProvider and GeminiLLMProvider make a live, uncached HTTP
call on every chat turn (see app/chat/service.py's module docstring) — a
transient failure here should not kill the whole conversation the way an
uncaught exception does. This wraps a single HTTP call with jittered
exponential backoff, retrying only failure modes that are actually
transient (a subset of 5xx status codes, 429 rate-limiting, and
network-level connection/timeout errors) — never a 4xx client error like
400/401/403/404, where retrying identically cannot succeed.
"""

import logging
import random
import time
from collections.abc import Callable

import httpx

logger = logging.getLogger(__name__)

_RETRYABLE_STATUS_CODES = {429, 500, 502, 503, 504}
_DEFAULT_MAX_ATTEMPTS = 3
_DEFAULT_BASE_DELAY_SECONDS = 1.0


def call_with_retries(
    make_request: Callable[[], httpx.Response],
    max_attempts: int = _DEFAULT_MAX_ATTEMPTS,
    base_delay_seconds: float = _DEFAULT_BASE_DELAY_SECONDS,
) -> httpx.Response:
    last_exc: Exception | None = None

    for attempt in range(max_attempts):
        try:
            response = make_request()
            response.raise_for_status()
            return response
        except httpx.HTTPStatusError as exc:
            if exc.response.status_code not in _RETRYABLE_STATUS_CODES:
                raise
            last_exc = exc
        except httpx.TransportError as exc:
            last_exc = exc

        if attempt < max_attempts - 1:
            delay = base_delay_seconds * (2**attempt) + random.uniform(0, base_delay_seconds)
            if isinstance(last_exc, httpx.HTTPStatusError):
                retry_after = last_exc.response.headers.get("retry-after")
                if retry_after is not None:
                    try:
                        delay = max(delay, float(retry_after))
                    except ValueError:
                        pass
            logger.warning(
                "Transient LLM API failure (attempt %d/%d): %s — retrying in %.1fs",
                attempt + 1,
                max_attempts,
                last_exc,
                delay,
            )
            time.sleep(delay)

    raise last_exc
```

- [ ] **Step 4: Run them, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_retry.py -v`
Expected: PASS, all 7 tests.

- [ ] **Step 5: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: 140 existing + 7 new all PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/app/providers/retry.py backend/tests/test_retry.py
git commit -m "feat: add jittered exponential-backoff retry helper for LLM vendor calls"
```

---

### Task 2: Wire retries into both LLM providers

**Files:**
- Modify: `backend/app/providers/anthropic.py`
- Modify: `backend/app/providers/gemini.py`
- Test: `backend/tests/test_anthropic_llm_provider.py` (extend)
- Test: `backend/tests/test_gemini_llm_provider.py` (extend)

**Interfaces:**
- Consumes: `call_with_retries` from Task 1. No change to either provider's public `generate()`/`close()` signature.

- [ ] **Step 1: Write the failing test for Anthropic retry integration**

Add to `backend/tests/test_anthropic_llm_provider.py` (reuse the file's existing `_client_returning` pattern for a normal single-response mock; for this test you need a multi-response mock, so write a small local handler):

```python
def test_generate_retries_on_transient_failure_then_succeeds(monkeypatch):
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: None)
    calls = {"count": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["count"] += 1
        if calls["count"] < 3:
            return httpx.Response(503)
        return httpx.Response(200, json={"content": [{"type": "text", "text": "ok"}], "stop_reason": "end_turn"})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="test-key", client=client)

    turn = provider.generate(system="s", history=[{"role": "user", "content": "hi"}], tools=[])

    assert turn.text == "ok"
    assert calls["count"] == 3


def test_generate_does_not_retry_on_permanent_client_error(monkeypatch):
    slept = []
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: slept.append(s))

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"error": "invalid api key"})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="bad-key", client=client)

    with pytest.raises(httpx.HTTPStatusError):
        provider.generate(system="s", history=[{"role": "user", "content": "hi"}], tools=[])

    assert slept == []
```

- [ ] **Step 2: Run them, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_anthropic_llm_provider.py -v`
Expected: the 2 new tests FAIL (no retry wired in yet — the first request's 503 propagates immediately as an uncaught `HTTPStatusError`, so `calls["count"]` stops at 1, not 3).

- [ ] **Step 3: Wire `call_with_retries` into `app/providers/anthropic.py`**

Add this import:

```python
from app.providers.retry import call_with_retries
```

Replace the request/status-check portion of `generate()`:

```python
        response = self._client.post(
            self._base_url,
            headers={
                "x-api-key": self._api_key,
                "anthropic-version": ANTHROPIC_VERSION,
                "content-type": "application/json",
            },
            json={
                "model": self._model,
                "max_tokens": self._max_tokens,
                "system": system,
                "messages": _translate_history(history),
                "tools": _translate_tools(tools),
            },
        )
        response.raise_for_status()
        payload = response.json()
```

with:

```python
        response = call_with_retries(
            lambda: self._client.post(
                self._base_url,
                headers={
                    "x-api-key": self._api_key,
                    "anthropic-version": ANTHROPIC_VERSION,
                    "content-type": "application/json",
                },
                json={
                    "model": self._model,
                    "max_tokens": self._max_tokens,
                    "system": system,
                    "messages": _translate_history(history),
                    "tools": _translate_tools(tools),
                },
            )
        )
        payload = response.json()
```

- [ ] **Step 4: Run them, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_anthropic_llm_provider.py -v`
Expected: PASS, all tests (including all pre-existing ones — a single-response mock still succeeds on attempt 1 with no behavior change).

- [ ] **Step 5: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/app/providers/anthropic.py backend/tests/test_anthropic_llm_provider.py
git commit -m "feat: retry transient failures in AnthropicLLMProvider.generate()"
```

- [ ] **Step 7: Write the failing test for Gemini retry integration**

Add to `backend/tests/test_gemini_llm_provider.py`:

```python
def test_generate_retries_on_transient_failure_then_succeeds(monkeypatch):
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: None)
    calls = {"count": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        calls["count"] += 1
        if calls["count"] < 3:
            return httpx.Response(503)
        return httpx.Response(
            200,
            json={"candidates": [{"content": {"parts": [{"text": "ok"}], "role": "model"}, "finishReason": "STOP"}]},
        )

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = GeminiLLMProvider(api_key="test-key", client=client)

    turn = provider.generate(system="s", history=[{"role": "user", "content": "hi"}], tools=[])

    assert turn.text == "ok"
    assert calls["count"] == 3


def test_generate_does_not_retry_on_permanent_client_error(monkeypatch):
    slept = []
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: slept.append(s))

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"error": "bad request"})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = GeminiLLMProvider(api_key="bad-key", client=client)

    with pytest.raises(httpx.HTTPStatusError):
        provider.generate(system="s", history=[{"role": "user", "content": "hi"}], tools=[])

    assert slept == []
```

- [ ] **Step 8: Run them, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_gemini_llm_provider.py -v`
Expected: the 2 new tests FAIL.

- [ ] **Step 9: Wire `call_with_retries` into `app/providers/gemini.py`**

Add the import `from app.providers.retry import call_with_retries` alongside the existing imports.

Replace:

```python
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
```

with:

```python
        response = call_with_retries(
            lambda: self._client.post(
                f"{self._base_url}/models/{self._model}:generateContent",
                headers={
                    # Header auth, never a ?key= query param: secrets must not
                    # appear in URLs, where they leak into logs and proxies.
                    "x-goog-api-key": self._api_key,
                    "content-type": "application/json",
                },
                json=body,
            )
        )
        payload = response.json()
```

- [ ] **Step 10: Run them, verify they pass, then run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 11: Commit**

```bash
git add backend/app/providers/gemini.py backend/tests/test_gemini_llm_provider.py
git commit -m "feat: retry transient failures in GeminiLLMProvider.generate()"
```

---

### Task 3: Honest error classification on `/chat`

**Files:**
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_chat_endpoint.py` (extend)

**Interfaces:** No new interfaces — this changes only `chat_endpoint`'s exception handling.

`json.JSONDecodeError` is a subclass of `ValueError`. The current `except (KeyError, ValueError)` clause silently swallows a malformed LLM-vendor response and reports it to the client as "Invalid history" (422) — misleading, since the client's history was fine and the failure was on the vendor side. Separately, an `httpx.HTTPStatusError`/`httpx.TransportError` that survives Task 2's retries (a sustained outage, or a genuinely non-retryable 4xx from the vendor) is currently completely uncaught here, producing FastAPI's opaque default 500.

- [ ] **Step 1: Write the failing tests**

Add to `backend/tests/test_chat_endpoint.py`:

```python
def test_chat_endpoint_returns_502_for_invalid_json_from_llm_provider(override_llm):
    # A malformed/unparseable body from the LLM vendor must NOT be reported
    # as "invalid history" (422) — that blames the client for a vendor-side
    # failure. json.JSONDecodeError is a ValueError subclass, so this
    # requires its own except clause ordered BEFORE the (KeyError, ValueError)
    # one, or the broader clause would catch it first.
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=b"not valid json{{{")

    mock_client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="test-key", client=mock_client)
    override_llm(provider)

    response = client.post("/chat", json={"message": "Hi"})

    assert response.status_code == 502
    assert "history" not in response.json()["detail"].lower()


def test_chat_endpoint_returns_503_when_llm_provider_is_unavailable(override_llm, monkeypatch):
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: None)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(503)

    mock_client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="test-key", client=mock_client)
    override_llm(provider)

    response = client.post("/chat", json={"message": "Hi"})

    assert response.status_code == 503


def test_chat_endpoint_returns_503_on_connection_failure(override_llm, monkeypatch):
    monkeypatch.setattr("app.providers.retry.time.sleep", lambda s: None)

    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("connection refused")

    mock_client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = AnthropicLLMProvider(api_key="test-key", client=mock_client)
    override_llm(provider)

    response = client.post("/chat", json={"message": "Hi"})

    assert response.status_code == 503
```

- [ ] **Step 2: Run them, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_chat_endpoint.py -v`
Expected: the 3 new tests FAIL (the first gets a 422 instead of 502; the other two get an unhandled 500 from FastAPI's default error handling instead of 503).

- [ ] **Step 3: Update `app/main.py`**

Add `import json` and `import httpx` near the top of the file, alongside the existing imports.

Replace `chat_endpoint`'s body:

```python
@app.post("/chat")
def chat_endpoint(
    request: ChatRequest, llm: LLMProvider = Depends(get_llm_provider)
) -> dict:
    try:
        return chat_turn(request.message, request.history, provider=llm)
    except (KeyError, ValueError) as e:
        raise HTTPException(status_code=422, detail=f"Invalid history: {e}") from e
```

with:

```python
@app.post("/chat")
def chat_endpoint(
    request: ChatRequest, llm: LLMProvider = Depends(get_llm_provider)
) -> dict:
    try:
        return chat_turn(request.message, request.history, provider=llm)
    except json.JSONDecodeError as e:
        # Must be caught before (KeyError, ValueError) below — JSONDecodeError
        # is a ValueError subclass, and a malformed response FROM the LLM
        # vendor is not the client's fault; misreporting it as "invalid
        # history" would send a debugging effort in the wrong direction.
        raise HTTPException(
            status_code=502, detail="The LLM provider returned an invalid response. Please try again."
        ) from e
    except (KeyError, ValueError) as e:
        raise HTTPException(status_code=422, detail=f"Invalid history: {e}") from e
    except (httpx.HTTPStatusError, httpx.TransportError) as e:
        # A transient failure that survived retry (see app/providers/retry.py),
        # or a non-retryable vendor-side error. Report a clean 503 rather than
        # FastAPI's opaque default 500, without leaking the vendor's raw
        # exception text to the client.
        raise HTTPException(
            status_code=503, detail="The LLM provider is temporarily unavailable. Please try again shortly."
        ) from e
```

- [ ] **Step 4: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_chat_endpoint.py -v`
Expected: PASS, all tests — including the pre-existing `test_chat_endpoint_returns_422_for_malformed_history`, which must still return 422 for a genuinely bad `role` value (a plain `ValueError`, not a `JSONDecodeError`).

- [ ] **Step 5: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 6: Manual live verification (non-blocking, requires a real API key)**

This worktree has a real `GEMINI_API_KEY`. From `backend/`, confirm the happy path still works end-to-end with retry logic now wrapping every call (it should be invisible when nothing is failing):

```bash
.venv/Scripts/python.exe -c "
from app.chat.service import chat_turn
result = chat_turn('What is the weather in Chennai?')
print(result['reply'])
"
```

Expected: a normal, correctly-grounded reply, with no visible behavior change from before this plan — retries only activate on actual failures, which this call should not hit.

- [ ] **Step 7: Commit**

```bash
git add backend/app/main.py backend/tests/test_chat_endpoint.py
git commit -m "fix: classify LLM provider failures honestly on /chat (502/503) instead of misreporting as invalid history"
```
