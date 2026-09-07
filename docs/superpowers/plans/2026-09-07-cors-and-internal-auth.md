# CORS and Internal Endpoint Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two small, independent hardening items, bundled into one sprint since both are small config-shaped changes to the same file: (1) `/internal/ingest/*` currently has no authentication at all — anyone reachable can trigger an ingestion cycle; (2) no CORS middleware exists, which blocks any browser-based client (a web frontend, or a web-based test harness) from calling this API at all, even for read-only GET routes.

**Architecture:** Both are additive to `app/main.py` — CORS via FastAPI's built-in `CORSMiddleware`, auth via a small `Depends`-based header check, matching the existing `get_llm_provider` dependency pattern already in this file.

**Tech Stack:** No new dependency — `CORSMiddleware` ships with FastAPI/Starlette already.

**Spec:** docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md (no spec changes — this closes gaps flagged in the original full-codebase review, not new scope).

## Design decision: internal-auth defaults to OPEN when unconfigured, not closed

If `Settings.internal_api_key` is unset (the default), the two `/internal/ingest/*` routes remain open — exactly like today — but log a warning on every request so the insecure state is visible, not silent (matching this project's established "make a degraded state visible" principle, used repeatedly this session: the forecast stale-fallback warning, the scheduler join-timeout warning). This is deliberate, not a weaker version of "real" auth: every manual test this whole session has hit these routes with no credentials, and a hard-fail-when-unconfigured design would break that today with no warning message pointing at why. Once `INTERNAL_API_KEY` is set in `.env`, the check becomes real and requests without a matching `X-Internal-API-Key` header get a 401.

## Design decision: CORS uses an explicit origin allowlist, not a wildcard, and does not enable credentials

The colleague's repo (reviewed earlier this session) combined `allow_origins=["*"]` with `allow_credentials=True` — an invalid combination browsers reject. This API has no cookie-based auth at all (chat/weather/alerts are all unauthenticated or header-keyed, never cookie-keyed), so there's no reason to enable credentialed CORS requests in the first place. `allow_credentials` is left at its default (`False`), and `allow_origins` is an explicit, configurable list — defaulting to common local frontend dev ports so a web-based frontend can be pointed at this API immediately, with a real deployment expected to override it via `.env`.

## Global Constraints

- No new dependency.
- Backward compatible by default: neither change alters behavior for the existing manual testing workflow used throughout this session unless a setting is explicitly configured (`INTERNAL_API_KEY` set; `CORS_ALLOWED_ORIGINS` overridden).
- No test may assume a `.env`-configured secret — tests must explicitly set/unset settings via `monkeypatch` + `get_settings.cache_clear()`, matching the established pattern already used throughout this codebase's test suite (e.g. `test_chat_endpoint.py`'s missing-API-key test).

---

### Task 1: CORS middleware and `/internal/ingest/*` authentication

**Files:**
- Modify: `backend/app/config.py`
- Modify: `backend/app/main.py`
- Modify: `backend/.env.example`
- Test: `backend/tests/test_cors.py`
- Test: `backend/tests/test_internal_auth.py`

**Interfaces:** No changes to any existing function signature or response shape — both additions are pure middleware/dependency wiring.

Current `backend/app/main.py` (read to confirm before editing — shown in full above via your own read).

- [ ] **Step 1: Add settings**

In `backend/app/config.py`, add to `Settings` after the existing `marine_ingestion_interval_seconds` field:

```python
    internal_api_key: str | None = None
    cors_allowed_origins: str = (
        "http://localhost:3000,http://localhost:5173,"
        "http://127.0.0.1:3000,http://127.0.0.1:5173"
    )
```

`cors_allowed_origins` is a plain comma-separated string (not a `list[str]` field) deliberately — pydantic-settings' handling of list-typed env vars requires JSON-encoding the env var value, which is an easy footgun for anyone editing `.env` by hand; a comma-separated string split at call time is simpler and matches this codebase's preference for the least surprising option.

Append to `backend/.env.example`:

```
# Shared secret required on X-Internal-API-Key for POST /internal/ingest/*.
# Left blank, these endpoints stay open (today's behavior) but log a
# warning on every request — set this before any real deployment or demo
# where the backend is reachable by anyone other than you.
INTERNAL_API_KEY=

# Comma-separated list of origins allowed to call this API from a browser.
# Defaults cover common local frontend dev ports; override for a real
# deployment. No CORS credentials are enabled — this API has no
# cookie-based auth, so there's nothing that needs them.
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://localhost:5173,http://127.0.0.1:3000,http://127.0.0.1:5173
```

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_cors.py`:

```python
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_allowed_origin_gets_cors_header():
    response = client.get("/health", headers={"Origin": "http://localhost:3000"})
    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "http://localhost:3000"


def test_disallowed_origin_does_not_get_cors_header():
    response = client.get("/health", headers={"Origin": "http://evil.example.com"})
    assert response.status_code == 200  # the request itself still succeeds...
    assert "access-control-allow-origin" not in response.headers  # ...but isn't CORS-approved


def test_credentials_are_not_enabled():
    response = client.get("/health", headers={"Origin": "http://localhost:3000"})
    assert "access-control-allow-credentials" not in response.headers
```

Create `backend/tests/test_internal_auth.py`:

```python
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app, verify_internal_api_key

client = TestClient(app)


def test_verify_internal_api_key_allows_when_no_key_configured(monkeypatch):
    # Calls the dependency function directly, in isolation — NOT through
    # the route/TestClient — specifically so this test never reaches the
    # real ingest route body (which would make a real SACHET network call).
    # Every other test in this project's suite avoids real network calls;
    # this is the one place doing so via TestClient would have broken that,
    # so the auth-open behavior is verified at the dependency-function
    # level instead.
    monkeypatch.setenv("INTERNAL_API_KEY", "")
    get_settings.cache_clear()
    try:
        result = verify_internal_api_key(x_internal_api_key=None)  # must not raise
        assert result is None
    finally:
        get_settings.cache_clear()


def test_ingest_alerts_rejects_missing_key_when_configured(monkeypatch):
    monkeypatch.setenv("INTERNAL_API_KEY", "test-secret-123")
    get_settings.cache_clear()
    try:
        response = client.post("/internal/ingest/alerts")
        assert response.status_code == 401
    finally:
        get_settings.cache_clear()


def test_ingest_alerts_rejects_wrong_key_when_configured(monkeypatch):
    monkeypatch.setenv("INTERNAL_API_KEY", "test-secret-123")
    get_settings.cache_clear()
    try:
        response = client.post(
            "/internal/ingest/alerts", headers={"X-Internal-API-Key": "wrong-key"}
        )
        assert response.status_code == 401
    finally:
        get_settings.cache_clear()


def test_ingest_marine_rejects_missing_key_when_configured(monkeypatch):
    monkeypatch.setenv("INTERNAL_API_KEY", "test-secret-123")
    get_settings.cache_clear()
    try:
        response = client.post("/internal/ingest/marine")
        assert response.status_code == 401
    finally:
        get_settings.cache_clear()
```

`verify_internal_api_key` must be importable from `app.main` (it will be, as a plain module-level function) for `test_verify_internal_api_key_allows_when_no_key_configured` to call it directly.

- [ ] **Step 3: Run them, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_cors.py tests/test_internal_auth.py -v`
Expected: `test_cors.py`'s tests FAIL (no CORS middleware registered yet, so no `access-control-allow-origin` header appears on any response). `test_internal_auth.py` fails to even collect — `from app.main import app, verify_internal_api_key` raises `ImportError`, since `verify_internal_api_key` doesn't exist until Step 4.

- [ ] **Step 4: Add CORS middleware and the auth dependency to `app/main.py`**

Add these imports near the top, alongside the existing ones:

```python
import logging

from fastapi import Header
from fastapi.middleware.cors import CORSMiddleware
```

Add `logger = logging.getLogger(__name__)` right after the imports, before the `lifespan` function.

Immediately after `app = FastAPI(title="WeatherGPT Backend", lifespan=lifespan)`, add:

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        origin.strip()
        for origin in get_settings().cors_allowed_origins.split(",")
        if origin.strip()
    ],
    allow_methods=["*"],
    allow_headers=["*"],
    # allow_credentials is deliberately left at its default (False) — this
    # API has no cookie-based auth, so there's nothing that needs it, and
    # combining a wildcard origin with credentials is an invalid
    # combination browsers reject outright (a real bug found in a
    # different WeatherGPT implementation reviewed earlier in this
    # project — this API avoids the whole category by using an explicit
    # origin list AND not needing credentials at all).
)
```

Add the auth dependency function, near `get_llm_provider` (after it, for example):

```python
def verify_internal_api_key(
    x_internal_api_key: str | None = Header(default=None, alias="X-Internal-API-Key"),
) -> None:
    settings = get_settings()
    if not settings.internal_api_key:
        logger.warning(
            "INTERNAL_API_KEY is not set — /internal/ingest/* endpoints are "
            "currently unauthenticated. Set it in backend/.env before any "
            "real deployment or demo reachable by anyone else."
        )
        return
    if x_internal_api_key != settings.internal_api_key:
        raise HTTPException(status_code=401, detail="Invalid or missing X-Internal-API-Key header")
```

Update both ingest routes to depend on it:

```python
@app.post("/internal/ingest/alerts", dependencies=[Depends(verify_internal_api_key)])
def trigger_alert_ingestion() -> dict[str, int]:
    count = ingest_alerts(SACHETWarningProvider())
    return {"ingested": count}
```

```python
@app.post("/internal/ingest/marine", dependencies=[Depends(verify_internal_api_key)])
def trigger_marine_ingestion() -> dict[str, int]:
    count = ingest_pfz_zones(INCOISMarineProvider())
    return {"ingested": count}
```

(`dependencies=[Depends(...)]` on the route decorator, rather than adding a parameter to the route function itself, since `verify_internal_api_key` returns nothing the route body needs — this is FastAPI's standard idiom for a dependency that only gates access, without threading an unused parameter through the function signature.)

- [ ] **Step 5: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_cors.py tests/test_internal_auth.py -v`
Expected: PASS, all tests.

- [ ] **Step 6: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS (in particular, confirm no other test file's `TestClient(app)` construction is affected by the new middleware/dependency — CORS only adds headers when an `Origin` header is present on the request, which no other existing test sends, and the auth dependency defaults to open when `INTERNAL_API_KEY` is unset, which is the case for every other test file's ambient settings).

- [ ] **Step 7: Commit**

```bash
git add backend/app/config.py backend/app/main.py backend/.env.example backend/tests/test_cors.py backend/tests/test_internal_auth.py
git commit -m "feat: add CORS middleware and shared-secret auth for /internal/ingest/*"
```
