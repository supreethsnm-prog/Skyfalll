# BHASHINI Voice Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add voice support — speech-to-text (ASR) and text-to-speech (TTS) via BHASHINI, India's government multilingual speech API — so `POST /voice/chat` can accept a spoken question as audio and reply with spoken audio, reusing the existing `chat_turn` tool-calling loop unchanged in between.

**Architecture:** `SpeechToTextProvider`/`TextToSpeechProvider` Protocols (mirroring every other provider in this codebase) implemented by one `BhashiniSpeechProvider`, which performs BHASHINI's real two-step flow: a "pipeline config" discovery call (returns a compute endpoint + a dynamic auth key), then a "pipeline compute" call to that returned endpoint (the actual ASR/TTS work). A new `app/voice/service.py` wires these around the *existing, unmodified* `chat_turn`: audio → transcribe → `chat_turn(transcript)` → synthesize(reply) → audio.

**Tech Stack:** Raw `httpx`, no new dependency — matches every other provider in this codebase. Reuses the existing `app/providers/retry.py::call_with_retries` for both BHASHINI calls, since transient failures apply here exactly as they do to the LLM providers.

**Spec:** docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md (§4's Voice bullet: "BHASHINI (ULCA) as primary... Google Cloud Speech as documented fallback" — this plan implements the primary path only; the documented fallback is out of scope, matching the spec's own framing of it as a future option, not a V1 requirement).

## Verified facts (checked against BHASHINI's real API documentation and, where possible, live against the real endpoint with the real credentials in this worktree's `.env` — use these exact shapes)

- **Discovery ("pipeline config") call**: `POST https://meity-auth.ulcacontrib.org/ulca/apis/v0/model/getModelsPipeline`. Headers: `userID`, `ulcaApiKey` (both plain header names, not `Authorization`). **Live-verified**: this worktree's real `BHASHINI_USER_ID` + `BHASHINI_INFERENCE_KEY` authenticate successfully against this real endpoint — confirmed by getting back a pipeline-specific error (`"Requested pipeline does not exist with this submitter!"`), not an auth error (401/403). Request body:
  ```json
  {
    "pipelineTasks": [
      {"taskType": "asr", "config": {"language": {"sourceLanguage": "hi"}}},
      {"taskType": "tts", "config": {"language": {"sourceLanguage": "hi"}}}
    ],
    "pipelineRequestConfig": {"pipelineId": "<see note below>"}
  }
  ```
  Response body (per BHASHINI's official documentation):
  ```json
  {
    "pipelineResponseConfig": [
      {"taskType": "asr", "config": [{"serviceId": "...", "modelId": "...", "language": {"sourceLanguage": "hi"}}]},
      {"taskType": "tts", "config": [{"serviceId": "...", "modelId": "...", "language": {"sourceLanguage": "hi"}, "supportedVoices": ["male", "female"]}]}
    ],
    "pipelineInferenceAPIEndPoint": {
      "callbackUrl": "https://...",
      "inferenceApiKey": {"name": "...", "value": "..."}
    }
  }
  ```
  **Critical**: `inferenceApiKey.name` is itself the HEADER NAME to use on the compute call (not a fixed header like `Authorization`) — the discovery response tells you both what header to send and what value to put in it. Never hardcode a header name for the compute call; always read it from this response.

- **Compute call** ("pipeline compute"): `POST <callbackUrl from discovery>`, header `<inferenceApiKey.name>: <inferenceApiKey.value>` (both values from the discovery response — a different key than the discovery call's own `ulcaApiKey`). For ASR:
  ```json
  {
    "pipelineTasks": [
      {"taskType": "asr", "config": {"language": {"sourceLanguage": "hi"}, "serviceId": "<from discovery config>", "audioFormat": "wav", "samplingRate": 16000}}
    ],
    "inputData": {"audio": [{"audioContent": "<base64 wav audio>"}]}
  }
  ```
  Response: `{"pipelineResponse": [{"taskType": "asr", "output": [{"source": "<transcribed text>"}]}]}`.
  For TTS:
  ```json
  {
    "pipelineTasks": [
      {"taskType": "tts", "config": {"language": {"sourceLanguage": "hi"}, "serviceId": "<from discovery config>", "gender": "female"}}
    ],
    "inputData": {"input": [{"source": "<text to speak>"}]}
  }
  ```
  Response: `{"pipelineResponse": [{"taskType": "tts", "audio": [{"audioContent": "<base64 wav audio>"}]}]}`.

- **`pipelineId` — a real, currently-unresolved gap, not a guess**: BHASHINI's own documentation states a `pipelineId` is obtained "via discussion with the Bhashini team, the ULCA Web portal, or a Pipeline Search call" — there is no way to derive it from the credentials alone. Two publicly-documented example IDs (MeitY's `64392f96daac500b55c543cd`, AI4Bharat's `643930aa521a4b1ba0f4c41d`) were tried live against this worktree's real credentials; neither is accessible to this account (`"does not exist with this submitter"` / `"does not exist"` respectively). **`Settings.bhashini_pipeline_id` must be a genuine, no-guessing-fallback required setting** — the provider raises a clear `ValueError` if it's unset, exactly matching the existing `AnthropicLLMProvider`/`GeminiLLMProvider` pattern for a missing API key. The user needs to obtain their real `pipelineId` from their ULCA account dashboard and set it in `.env` before this feature can be exercised live — this is flagged explicitly in this task's final manual-verification step, not silently worked around.
- **Audio format**: BHASHINI's documented example uses WAV at 16kHz for ASR input, and returns WAV (implied by symmetry with input, and by the response field being named identically to the input's `audioContent`) for TTS output. This plan scopes `/voice/chat` to accept WAV input only for V1 — transcoding other formats (webm/mp3/ogg, which real browsers/mobile clients often record in) would need a new audio-processing dependency, out of scope for this plan; this is a documented, accepted V1 limitation, not an oversight.

## Global Constraints

- Provider abstraction pattern (established every prior sprint): `Protocol` + canonical `@dataclass` + a concrete class with `client: httpx.Client | None = None` / `self._owns_client = client is None`.
- **Client lifecycle**: `generate`/`transcribe`/`synthesize` must never close a self-owned client mid-call-sequence — the discovery call and compute call for one operation happen on the SAME client instance within one method call, so this is naturally fine, but `close()` must still exist and only close a self-owned client, matching every other provider (a Critical bug in an earlier sprint came from getting exactly this wrong for a provider that's called repeatedly — here, `transcribe`/`synthesize` each make exactly 2 HTTP calls per invocation but the provider object itself can be reused across multiple `transcribe`/`synthesize` calls, so the same "don't close inside the method, only in an explicit `close()`" discipline applies).
- Reuse `app/providers/retry.py::call_with_retries` for BOTH BHASHINI calls (discovery and compute) — do not write a second retry implementation.
- No new dependency — no audio transcoding library, no BHASHINI SDK (none officially exists anyway; this is a plain REST API).
- Response hygiene: `raw_payload` (or equivalent) excluded from client-facing responses, matching every other provider/service in this codebase.
- Tests must never make a real network call to BHASHINI (rate-limited to ~50 requests/hour in production use) — every test uses `httpx.MockTransport` with the shapes verified above.

---

### Task 1: Speech provider abstraction

**Files:**
- Create: `backend/app/providers/speech.py`

**Interfaces:**
- Produces: `TranscriptionResult` dataclass (`text: str`, `source_language: str`, `raw_payload: dict`), `SynthesisResult` dataclass (`audio_base64: str`, `audio_format: str`, `raw_payload: dict`), `SpeechToTextProvider` Protocol (`transcribe(self, audio_base64: str, audio_format: str, language: str) -> TranscriptionResult`), `TextToSpeechProvider` Protocol (`synthesize(self, text: str, language: str) -> SynthesisResult`). Consumed by Task 2.

- [ ] **Step 1: Write `app/providers/speech.py`**

```python
from dataclasses import dataclass
from typing import Any, Protocol


@dataclass
class TranscriptionResult:
    text: str
    source_language: str
    raw_payload: dict[str, Any]


@dataclass
class SynthesisResult:
    audio_base64: str
    audio_format: str
    raw_payload: dict[str, Any]


class SpeechToTextProvider(Protocol):
    def transcribe(self, audio_base64: str, audio_format: str, language: str) -> TranscriptionResult: ...


class TextToSpeechProvider(Protocol):
    def synthesize(self, text: str, language: str) -> SynthesisResult: ...
```

This file has no tests of its own (pure dataclasses/Protocols, no logic) — matches the existing pattern for every other `app/providers/<domain>.py` abstraction file in this codebase (e.g. `app/providers/weather.py`, `app/providers/marine.py`), none of which have a dedicated test file either.

- [ ] **Step 2: Confirm it imports cleanly**

Run from `backend/`: `.venv/Scripts/python.exe -c "from app.providers.speech import TranscriptionResult, SynthesisResult, SpeechToTextProvider, TextToSpeechProvider; print('ok')"`
Expected: prints `ok`.

- [ ] **Step 3: Commit**

```bash
git add backend/app/providers/speech.py
git commit -m "feat: add SpeechToTextProvider/TextToSpeechProvider abstraction"
```

---

### Task 2: BhashiniSpeechProvider — the two-step ULCA discovery→compute flow

**Files:**
- Modify: `backend/app/config.py`
- Create: `backend/app/providers/bhashini.py`
- Modify: `backend/.env.example`
- Test: `backend/tests/test_bhashini_provider.py`

**Interfaces:**
- Consumes: `TranscriptionResult`, `SynthesisResult` (Task 1); `call_with_retries` (`app/providers/retry.py`, already exists).
- Produces: `BhashiniSpeechProvider` implementing both `SpeechToTextProvider` and `TextToSpeechProvider` on one class (one provider, two capabilities — BHASHINI's own discovery call can request both `asr` and `tts` task types in a single config call, so one class naturally covers both rather than being split).

This is the most design-heavy task in this plan — the two-step flow, and specifically reading the compute-call auth header NAME (not just its value) dynamically out of the discovery response, is the one place a subtly wrong implementation would look plausible but be broken.

- [ ] **Step 1: Add BHASHINI settings to `app/config.py`**

Add to `Settings`, after the existing `cors_allowed_origins` field:

```python
    bhashini_user_id: str | None = None
    bhashini_inference_key: str | None = None
    bhashini_pipeline_id: str | None = None
```

Append to `backend/.env.example`:

```
# BHASHINI (ULCA) voice — speech-to-text and text-to-speech.
# BHASHINI_PIPELINE_ID has no default and cannot be guessed or derived from
# the other two credentials — BHASHINI's own docs say it comes from "the
# ULCA Web portal, discussion with the Bhashini team, or a Pipeline Search
# call." Log into https://bhashini.gov.in/ulca and find it under your
# profile/pipeline dashboard. Until this is set, voice endpoints return a
# clear 503, the same way /chat does when no LLM key is configured.
BHASHINI_USER_ID=
BHASHINI_INFERENCE_KEY=
BHASHINI_PIPELINE_ID=
```

- [ ] **Step 2: Write the failing tests**

Create `backend/tests/test_bhashini_provider.py`:

```python
import base64
import json

import httpx
import pytest

from app.providers.bhashini import BhashiniSpeechProvider

_DISCOVERY_RESPONSE = {
    "pipelineResponseConfig": [
        {
            "taskType": "asr",
            "config": [{"serviceId": "asr-service-1", "modelId": "asr-model-1", "language": {"sourceLanguage": "hi"}}],
        },
        {
            "taskType": "tts",
            "config": [{"serviceId": "tts-service-1", "modelId": "tts-model-1", "language": {"sourceLanguage": "hi"}}],
        },
    ],
    "pipelineInferenceAPIEndPoint": {
        "callbackUrl": "https://dhruva-api.bhashini.gov.in/services/inference/pipeline",
        "inferenceApiKey": {"name": "X-Compute-Auth-Key", "value": "compute-secret-abc"},
    },
}

_ASR_COMPUTE_RESPONSE = {
    "pipelineResponse": [{"taskType": "asr", "output": [{"source": "मुंबई में मौसम कैसा है"}]}]
}

_TTS_COMPUTE_RESPONSE = {
    "pipelineResponse": [{"taskType": "tts", "audio": [{"audioContent": "ZmFrZS13YXYtYnl0ZXM="}]}]
}


def _client_for(discovery_response, compute_response, capture=None):
    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        if "pipelineRequestConfig" in body:
            if capture is not None:
                capture["discovery_request"] = body
                capture["discovery_headers"] = dict(request.headers)
            return httpx.Response(200, json=discovery_response)
        if capture is not None:
            capture["compute_request"] = body
            capture["compute_url"] = str(request.url)
            capture["compute_headers"] = dict(request.headers)
        return httpx.Response(200, json=compute_response)

    return httpx.Client(transport=httpx.MockTransport(handler))


def test_raises_without_credentials():
    with pytest.raises(ValueError, match="BHASHINI_USER_ID"):
        BhashiniSpeechProvider(user_id=None, inference_key="k", pipeline_id="p")


def test_raises_without_pipeline_id():
    with pytest.raises(ValueError, match="BHASHINI_PIPELINE_ID"):
        BhashiniSpeechProvider(user_id="u", inference_key="k", pipeline_id=None)


def test_transcribe_performs_discovery_then_compute_with_dynamic_auth_header():
    capture = {}
    client = _client_for(_DISCOVERY_RESPONSE, _ASR_COMPUTE_RESPONSE, capture)
    provider = BhashiniSpeechProvider(user_id="test-user", inference_key="test-key", pipeline_id="test-pipeline", client=client)

    result = provider.transcribe(audio_base64="ZmFrZS1hdWRpbw==", audio_format="wav", language="hi")

    assert result.text == "मुंबई में मौसम कैसा है"
    assert result.source_language == "hi"

    # Discovery call used the fixed userID/ulcaApiKey headers.
    assert capture["discovery_headers"]["userid"] == "test-user"
    assert capture["discovery_headers"]["ulcaapikey"] == "test-key"
    assert capture["discovery_request"]["pipelineRequestConfig"]["pipelineId"] == "test-pipeline"

    # Compute call went to the discovery-provided callbackUrl, used the
    # DYNAMIC header name+value from the discovery response (not a
    # hardcoded header name), and included the serviceId discovery returned.
    assert capture["compute_url"] == "https://dhruva-api.bhashini.gov.in/services/inference/pipeline"
    assert capture["compute_headers"]["x-compute-auth-key"] == "compute-secret-abc"
    assert capture["compute_request"]["pipelineTasks"][0]["config"]["serviceId"] == "asr-service-1"
    assert capture["compute_request"]["inputData"]["audio"][0]["audioContent"] == "ZmFrZS1hdWRpbw=="


def test_synthesize_performs_discovery_then_compute():
    capture = {}
    client = _client_for(_DISCOVERY_RESPONSE, _TTS_COMPUTE_RESPONSE, capture)
    provider = BhashiniSpeechProvider(user_id="test-user", inference_key="test-key", pipeline_id="test-pipeline", client=client)

    result = provider.synthesize(text="मुंबई में आज बारिश होगी", language="hi")

    assert result.audio_base64 == "ZmFrZS13YXYtYnl0ZXM="
    assert result.audio_format == "wav"
    assert capture["compute_request"]["pipelineTasks"][0]["config"]["serviceId"] == "tts-service-1"
    assert capture["compute_request"]["inputData"]["input"][0]["source"] == "मुंबई में आज बारिश होगी"


def test_transcribe_raises_on_discovery_http_error():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"code": "400 BAD_REQUEST", "message": "boom"})

    client = httpx.Client(transport=httpx.MockTransport(handler))
    provider = BhashiniSpeechProvider(user_id="u", inference_key="k", pipeline_id="p", client=client)

    with pytest.raises(httpx.HTTPStatusError):
        provider.transcribe(audio_base64="ZmFrZQ==", audio_format="wav", language="hi")


def test_close_only_closes_self_owned_client():
    client = _client_for(_DISCOVERY_RESPONSE, _ASR_COMPUTE_RESPONSE)
    provider = BhashiniSpeechProvider(user_id="u", inference_key="k", pipeline_id="p", client=client)
    provider.close()
    assert not client.is_closed

    provider2 = BhashiniSpeechProvider(user_id="u", inference_key="k", pipeline_id="p")
    assert provider2._owns_client is True
```

- [ ] **Step 3: Run them, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_bhashini_provider.py -v`
Expected: FAIL — `app.providers.bhashini` does not exist.

- [ ] **Step 4: Write `app/providers/bhashini.py`**

```python
"""BHASHINI (ULCA) speech-to-text/text-to-speech adapter.

BHASHINI's API is a two-step flow, unlike every other provider in this
codebase: a "pipeline config" discovery call returns a compute endpoint
URL (callbackUrl) AND an auth header — both its NAME and its VALUE — that
must be used for the second "pipeline compute" call, which does the actual
work. The header name is not fixed (never hardcode it); it comes back in
the discovery response every time.

Never wrapped in a cache (see app/chat/service.py's docstring for the
general principle) — a transcription/synthesis result is specific to one
utterance, there's nothing meaningful to cache it against.
"""

import base64
from dataclasses import dataclass
from typing import Any

import httpx

from app.config import get_settings
from app.providers.retry import call_with_retries
from app.providers.speech import SynthesisResult, TranscriptionResult

BHASHINI_DISCOVERY_URL = "https://meity-auth.ulcacontrib.org/ulca/apis/v0/model/getModelsPipeline"

_ASR_AUDIO_FORMAT = "wav"
_ASR_SAMPLING_RATE = 16000
_TTS_GENDER = "female"


@dataclass
class _PipelineConfig:
    callback_url: str
    auth_header_name: str
    auth_header_value: str
    service_id: str


class BhashiniSpeechProvider:
    def __init__(
        self,
        user_id: str | None = None,
        inference_key: str | None = None,
        pipeline_id: str | None = None,
        discovery_url: str = BHASHINI_DISCOVERY_URL,
        client: httpx.Client | None = None,
    ):
        settings = get_settings()
        self._user_id = user_id if user_id is not None else settings.bhashini_user_id
        self._inference_key = inference_key if inference_key is not None else settings.bhashini_inference_key
        self._pipeline_id = pipeline_id if pipeline_id is not None else settings.bhashini_pipeline_id

        if not self._user_id or not self._inference_key:
            raise ValueError(
                "BHASHINI_USER_ID and BHASHINI_INFERENCE_KEY must both be set. "
                "Set them in backend/.env or as environment variables to enable voice."
            )
        if not self._pipeline_id:
            raise ValueError(
                "BHASHINI_PIPELINE_ID is not set. This cannot be guessed or derived "
                "from the other credentials — log into https://bhashini.gov.in/ulca "
                "and find it under your profile/pipeline dashboard, then set it in "
                "backend/.env."
            )

        self._discovery_url = discovery_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=30.0)

    def _discover(self, task_type: str, language: str) -> _PipelineConfig:
        response = call_with_retries(
            lambda: self._client.post(
                self._discovery_url,
                headers={
                    "userID": self._user_id,
                    "ulcaApiKey": self._inference_key,
                    "Content-Type": "application/json",
                },
                json={
                    "pipelineTasks": [
                        {"taskType": task_type, "config": {"language": {"sourceLanguage": language}}}
                    ],
                    "pipelineRequestConfig": {"pipelineId": self._pipeline_id},
                },
            )
        )
        payload = response.json()

        task_config = next(
            task["config"][0]
            for task in payload["pipelineResponseConfig"]
            if task["taskType"] == task_type
        )
        endpoint = payload["pipelineInferenceAPIEndPoint"]
        return _PipelineConfig(
            callback_url=endpoint["callbackUrl"],
            auth_header_name=endpoint["inferenceApiKey"]["name"],
            auth_header_value=endpoint["inferenceApiKey"]["value"],
            service_id=task_config["serviceId"],
        )

    def transcribe(self, audio_base64: str, audio_format: str, language: str) -> TranscriptionResult:
        config = self._discover("asr", language)
        response = call_with_retries(
            lambda: self._client.post(
                config.callback_url,
                headers={config.auth_header_name: config.auth_header_value, "Content-Type": "application/json"},
                json={
                    "pipelineTasks": [
                        {
                            "taskType": "asr",
                            "config": {
                                "language": {"sourceLanguage": language},
                                "serviceId": config.service_id,
                                "audioFormat": audio_format,
                                "samplingRate": _ASR_SAMPLING_RATE,
                            },
                        }
                    ],
                    "inputData": {"audio": [{"audioContent": audio_base64}]},
                },
            )
        )
        payload = response.json()
        text = payload["pipelineResponse"][0]["output"][0]["source"]
        return TranscriptionResult(text=text, source_language=language, raw_payload=payload)

    def synthesize(self, text: str, language: str) -> SynthesisResult:
        config = self._discover("tts", language)
        response = call_with_retries(
            lambda: self._client.post(
                config.callback_url,
                headers={config.auth_header_name: config.auth_header_value, "Content-Type": "application/json"},
                json={
                    "pipelineTasks": [
                        {
                            "taskType": "tts",
                            "config": {
                                "language": {"sourceLanguage": language},
                                "serviceId": config.service_id,
                                "gender": _TTS_GENDER,
                            },
                        }
                    ],
                    "inputData": {"input": [{"source": text}]},
                },
            )
        )
        payload = response.json()
        audio_content = payload["pipelineResponse"][0]["audio"][0]["audioContent"]
        return SynthesisResult(audio_base64=audio_content, audio_format=_ASR_AUDIO_FORMAT, raw_payload=payload)

    def close(self) -> None:
        if self._owns_client:
            self._client.close()
```

Note: `import base64` is unused in this file as written — the audio content passed in and returned is ALREADY a base64 string at every boundary (the caller/endpoint layer is responsible for encoding/decoding raw bytes, this provider only ever handles the base64-string form). Remove the unused import if your linter flags it.

- [ ] **Step 5: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_bhashini_provider.py -v`
Expected: PASS, all 6 tests.

- [ ] **Step 6: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: 181 existing + 6 new all PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/app/config.py backend/app/providers/bhashini.py backend/.env.example backend/tests/test_bhashini_provider.py
git commit -m "feat: add BhashiniSpeechProvider (two-step ULCA discovery+compute flow)"
```

---

### Task 3: Voice orchestration service

**Files:**
- Create: `backend/app/voice/__init__.py` (empty)
- Create: `backend/app/voice/service.py`
- Test: `backend/tests/test_voice_service.py`

**Interfaces:**
- Consumes: `SpeechToTextProvider`, `TextToSpeechProvider` (Task 1/2); `chat_turn` (`app/chat/service.py`, unmodified).
- Produces: `voice_chat(audio_base64: str, audio_format: str, language: str, history: list[dict] | None = None, stt_provider=None, tts_provider=None, chat_fn=None) -> dict`, consumed by Task 4.

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_voice_service.py`:

```python
from app.providers.speech import SynthesisResult, TranscriptionResult
from app.voice.service import voice_chat


class _FakeSTT:
    def __init__(self, result: TranscriptionResult):
        self._result = result
        self.calls = []

    def transcribe(self, audio_base64, audio_format, language):
        self.calls.append((audio_base64, audio_format, language))
        return self._result


class _FakeTTS:
    def __init__(self, result: SynthesisResult):
        self._result = result
        self.calls = []

    def synthesize(self, text, language):
        self.calls.append((text, language))
        return self._result


def _fake_chat_turn(message, history=None, provider=None):
    return {"reply": f"Reply to: {message}", "history": (history or []) + [{"role": "user", "content": message}]}


def test_voice_chat_transcribes_chats_and_synthesizes():
    stt = _FakeSTT(TranscriptionResult(text="मुंबई में मौसम कैसा है", source_language="hi", raw_payload={}))
    tts = _FakeTTS(SynthesisResult(audio_base64="ZmFrZS1hdWRpbw==", audio_format="wav", raw_payload={}))

    result = voice_chat(
        audio_base64="aW5wdXQtYXVkaW8=",
        audio_format="wav",
        language="hi",
        stt_provider=stt,
        tts_provider=tts,
        chat_fn=_fake_chat_turn,
    )

    assert result["transcript"] == "मुंबई में मौसम कैसा है"
    assert result["reply_text"] == "Reply to: मुंबई में मौसम कैसा है"
    assert result["reply_audio_base64"] == "ZmFrZS1hdWRpbw=="
    assert stt.calls == [("aW5wdXQtYXVkaW8=", "wav", "hi")]
    assert tts.calls == [("Reply to: मुंबई में मौसम कैसा है", "hi")]


def test_voice_chat_passes_history_through_to_chat_fn():
    stt = _FakeSTT(TranscriptionResult(text="hello", source_language="en", raw_payload={}))
    tts = _FakeTTS(SynthesisResult(audio_base64="YXVkaW8=", audio_format="wav", raw_payload={}))
    prior_history = [{"role": "user", "content": "earlier"}]

    result = voice_chat(
        audio_base64="YQ==",
        audio_format="wav",
        language="en",
        history=prior_history,
        stt_provider=stt,
        tts_provider=tts,
        chat_fn=_fake_chat_turn,
    )

    assert result["history"][0] == {"role": "user", "content": "earlier"}
    assert result["history"][-1] == {"role": "user", "content": "hello"}


def test_voice_chat_returns_transcript_even_if_reply_is_empty():
    stt = _FakeSTT(TranscriptionResult(text="silence test", source_language="en", raw_payload={}))
    tts = _FakeTTS(SynthesisResult(audio_base64="", audio_format="wav", raw_payload={}))

    def _empty_chat_turn(message, history=None, provider=None):
        return {"reply": "", "history": []}

    result = voice_chat(
        audio_base64="eA==",
        audio_format="wav",
        language="en",
        stt_provider=stt,
        tts_provider=tts,
        chat_fn=_empty_chat_turn,
    )

    assert result["transcript"] == "silence test"
    assert result["reply_text"] == ""
```

- [ ] **Step 2: Run them, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_voice_service.py -v`
Expected: FAIL — `app.voice.service` does not exist.

- [ ] **Step 3: Create `backend/app/voice/__init__.py`** (empty file).

- [ ] **Step 4: Write `app/voice/service.py`**

```python
"""Voice orchestration: audio in -> transcript -> chat_turn -> reply -> audio out.

chat_turn (app/chat/service.py) is used completely unmodified — voice is a
new INPUT/OUTPUT modality around the exact same tool-calling loop text chat
already uses, not a separate conversational path. This is deliberate:
every guarantee chat_turn already has (grounding via tools, retry-backed
LLM calls, the multi-round tool-iteration cap) applies to voice for free.
"""

from collections.abc import Callable

from app.chat.service import chat_turn
from app.providers.bhashini import BhashiniSpeechProvider
from app.providers.speech import SpeechToTextProvider, TextToSpeechProvider


def voice_chat(
    audio_base64: str,
    audio_format: str,
    language: str,
    history: list[dict] | None = None,
    stt_provider: SpeechToTextProvider | None = None,
    tts_provider: TextToSpeechProvider | None = None,
    chat_fn: Callable[..., dict] = chat_turn,
) -> dict:
    owns_stt = stt_provider is None
    owns_tts = tts_provider is None
    stt = stt_provider or BhashiniSpeechProvider()
    tts = tts_provider or BhashiniSpeechProvider()
    try:
        transcription = stt.transcribe(audio_base64=audio_base64, audio_format=audio_format, language=language)
        chat_result = chat_fn(transcription.text, history)
        reply_text = chat_result["reply"]

        reply_audio_base64 = ""
        if reply_text:
            synthesis = tts.synthesize(text=reply_text, language=language)
            reply_audio_base64 = synthesis.audio_base64

        return {
            "transcript": transcription.text,
            "reply_text": reply_text,
            "reply_audio_base64": reply_audio_base64,
            "history": chat_result["history"],
        }
    finally:
        if owns_stt and hasattr(stt, "close"):
            stt.close()
        if owns_tts and tts is not stt and hasattr(tts, "close"):
            tts.close()
```

Note `owns_stt`/`owns_tts` each construct their OWN `BhashiniSpeechProvider()` instance when not injected (two separate instances, two separate underlying `httpx.Client`s) — simpler and safer than trying to share one instance across both roles, at the cost of one extra client construction per voice turn. Given voice turns are inherently latency-heavy already (two round trips to BHASHINI plus the full chat loop), this is a reasonable, deliberate simplicity-over-micro-optimization trade-off, consistent with this codebase's general preference (e.g. `app/chat/tools.py` doesn't share HTTP clients across the five different services it wraps either).

- [ ] **Step 5: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_voice_service.py -v`
Expected: PASS, all 3 tests.

- [ ] **Step 6: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/app/voice/__init__.py backend/app/voice/service.py backend/tests/test_voice_service.py
git commit -m "feat: add voice_chat orchestration wiring STT -> chat_turn -> TTS"
```

---

### Task 4: `POST /voice/chat` and `GET /voice/languages` endpoints

**Files:**
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_voice_endpoint.py`

**Interfaces:** New routes only — no changes to any existing route or function signature.

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/test_voice_endpoint.py`:

```python
import base64
import io

from fastapi.testclient import TestClient

from app.main import app, get_stt_provider, get_tts_provider
from app.providers.speech import SynthesisResult, TranscriptionResult

client = TestClient(app)


class _FakeSTT:
    def transcribe(self, audio_base64, audio_format, language):
        return TranscriptionResult(text="test transcript", source_language=language, raw_payload={})

    def close(self):
        pass


class _FakeTTS:
    def synthesize(self, text, language):
        return SynthesisResult(audio_base64="ZmFrZS1hdWRpbw==", audio_format="wav", raw_payload={})

    def close(self):
        pass


def _override(fake_stt=None, fake_tts=None):
    if fake_stt is not None:
        app.dependency_overrides[get_stt_provider] = lambda: fake_stt
    if fake_tts is not None:
        app.dependency_overrides[get_tts_provider] = lambda: fake_tts


def _clear_overrides():
    app.dependency_overrides.pop(get_stt_provider, None)
    app.dependency_overrides.pop(get_tts_provider, None)


def test_voice_languages_returns_a_static_list():
    response = client.get("/voice/languages")
    assert response.status_code == 200
    body = response.json()
    assert "languages" in body
    assert any(lang["code"] == "hi" for lang in body["languages"])
    assert any(lang["code"] == "en" for lang in body["languages"])


def test_voice_chat_returns_transcript_and_reply_audio(monkeypatch):
    from app.providers.llm import LLMTurn
    from tests.conftest import FakeLLMProvider
    from app.main import get_llm_provider

    fake_llm = FakeLLMProvider([LLMTurn(text="Here is your reply.", tool_calls=[], stop_reason="end_turn")])
    app.dependency_overrides[get_llm_provider] = lambda: fake_llm
    _override(fake_stt=_FakeSTT(), fake_tts=_FakeTTS())
    try:
        wav_bytes = b"RIFF....WAVEfmt fake wav bytes"
        response = client.post(
            "/voice/chat",
            files={"audio": ("test.wav", io.BytesIO(wav_bytes), "audio/wav")},
            data={"language": "hi"},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["transcript"] == "test transcript"
        assert body["reply_text"] == "Here is your reply."
        assert body["reply_audio_base64"] == "ZmFrZS1hdWRpbw=="
    finally:
        _clear_overrides()
        app.dependency_overrides.pop(get_llm_provider, None)


def test_voice_chat_rejects_non_wav_upload():
    response = client.post(
        "/voice/chat",
        files={"audio": ("test.mp3", io.BytesIO(b"fake mp3 bytes"), "audio/mpeg")},
        data={"language": "hi"},
    )
    assert response.status_code == 422


def test_voice_chat_returns_503_when_bhashini_not_configured(monkeypatch):
    monkeypatch.setenv("BHASHINI_USER_ID", "")
    monkeypatch.setenv("BHASHINI_INFERENCE_KEY", "")
    monkeypatch.setenv("BHASHINI_PIPELINE_ID", "")
    from app.config import get_settings

    get_settings.cache_clear()
    try:
        wav_bytes = b"RIFF....WAVEfmt fake wav bytes"
        response = client.post(
            "/voice/chat",
            files={"audio": ("test.wav", io.BytesIO(wav_bytes), "audio/wav")},
            data={"language": "hi"},
        )
        assert response.status_code == 503
    finally:
        get_settings.cache_clear()
```

- [ ] **Step 2: Run them, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_voice_endpoint.py -v`
Expected: FAIL — no `/voice/*` routes, `get_stt_provider`/`get_tts_provider` don't exist.

- [ ] **Step 3: Add the routes to `app/main.py`**

Add these imports alongside the existing ones:

```python
from fastapi import File, Form, UploadFile

from app.providers.bhashini import BhashiniSpeechProvider
from app.providers.speech import SpeechToTextProvider, TextToSpeechProvider
from app.voice.service import voice_chat
```

Add near `get_llm_provider` (same generator-dependency pattern, same rationale: these providers make live, uncached, per-call HTTP requests, so tests need a real `Depends` seam rather than relying on a cache-miss-only path):

```python
_STATIC_VOICE_LANGUAGES = [
    {"code": "as", "name": "Assamese"}, {"code": "bn", "name": "Bengali"},
    {"code": "brx", "name": "Bodo"}, {"code": "doi", "name": "Dogri"},
    {"code": "en", "name": "English"}, {"code": "gom", "name": "Konkani"},
    {"code": "gu", "name": "Gujarati"}, {"code": "hi", "name": "Hindi"},
    {"code": "kn", "name": "Kannada"}, {"code": "ks", "name": "Kashmiri"},
    {"code": "mai", "name": "Maithili"}, {"code": "ml", "name": "Malayalam"},
    {"code": "mni", "name": "Manipuri"}, {"code": "mr", "name": "Marathi"},
    {"code": "ne", "name": "Nepali"}, {"code": "or", "name": "Odia"},
    {"code": "pa", "name": "Punjabi"}, {"code": "sa", "name": "Sanskrit"},
    {"code": "sat", "name": "Santali"}, {"code": "sd", "name": "Sindhi"},
    {"code": "ta", "name": "Tamil"}, {"code": "te", "name": "Telugu"},
    {"code": "ur", "name": "Urdu"},
]


@app.get("/voice/languages")
def voice_languages_endpoint() -> dict:
    return {"languages": _STATIC_VOICE_LANGUAGES, "count": len(_STATIC_VOICE_LANGUAGES)}


def get_stt_provider() -> Generator[SpeechToTextProvider, None, None]:
    try:
        provider = BhashiniSpeechProvider()
    except ValueError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e
    try:
        yield provider
    finally:
        provider.close()


def get_tts_provider() -> Generator[TextToSpeechProvider, None, None]:
    try:
        provider = BhashiniSpeechProvider()
    except ValueError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e
    try:
        yield provider
    finally:
        provider.close()


@app.post("/voice/chat")
def voice_chat_endpoint(
    audio: UploadFile = File(...),
    language: str = Form("hi"),
    stt: SpeechToTextProvider = Depends(get_stt_provider),
    tts: TextToSpeechProvider = Depends(get_tts_provider),
) -> dict:
    if not (audio.content_type or "").endswith("wav") and not audio.filename.lower().endswith(".wav"):
        raise HTTPException(
            status_code=422,
            detail="Only WAV audio is supported in this version. Convert your audio to WAV before uploading.",
        )
    audio_bytes = audio.file.read()
    audio_base64 = base64.b64encode(audio_bytes).decode("ascii")
    return voice_chat(
        audio_base64=audio_base64,
        audio_format="wav",
        language=language,
        stt_provider=stt,
        tts_provider=tts,
    )
```

Add `import base64` to the top-level imports if not already present (it isn't — check first).

Note: `get_stt_provider`/`get_tts_provider` are separate dependency functions (each constructing its own `BhashiniSpeechProvider()`) even though they wrap the same class — this mirrors `voice_chat`'s own two-separate-instances design from Task 3, and lets a test override just one of the two independently if only one needs faking for a given test case.

- [ ] **Step 4: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_voice_endpoint.py -v`
Expected: PASS, all 4 tests.

- [ ] **Step 5: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/app/main.py backend/tests/test_voice_endpoint.py
git commit -m "feat: add POST /voice/chat and GET /voice/languages endpoints"
```

- [ ] **Step 7: Manual live verification (non-blocking, EXTERNALLY BLOCKED pending a real `BHASHINI_PIPELINE_ID`)**

This step cannot run until `BHASHINI_PIPELINE_ID` is set to a real value obtained from the user's ULCA dashboard (see this plan's "Verified facts" section — this is a genuine external dependency, not a guess or an oversight). If it's available by the time this task runs, attempt a real round trip:

```bash
.venv/Scripts/python.exe -c "
from app.providers.bhashini import BhashiniSpeechProvider
provider = BhashiniSpeechProvider()
result = provider.synthesize(text='नमस्ते, यह एक परीक्षण है', language='hi')
print('Got', len(result.audio_base64), 'base64 chars back, format:', result.audio_format)
provider.close()
"
```

If `BHASHINI_PIPELINE_ID` is still unset when this task is reached, report this step as SKIPPED (not failed, not faked) with the reason, and note in the task report that this plan's implementation is fully built and unit-tested against BHASHINI's documented API shapes, but has not yet been proven against a real successful response — this is an accurate, honest status, not a gap to hide.
