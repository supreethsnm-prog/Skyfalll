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
