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
_MAX_DELAY_SECONDS = 30.0


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
            delay = min(delay, _MAX_DELAY_SECONDS)
            logger.warning(
                "Transient LLM API failure (attempt %d/%d): %s — retrying in %.1fs",
                attempt + 1,
                max_attempts,
                last_exc,
                delay,
            )
            time.sleep(delay)

    raise last_exc
