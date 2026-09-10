# Bhashini STT/TTS Auth Fix + NMT Translation — Backend Done, Frontend Handoff

> **For agentic workers (Claude reading this to wire the Flutter app):** the backend work below is MERGED in this worktree and live-verified. Your job is frontend-only: add `TranslateApi` + optional UI strings translation + unhide voice behind `kVoiceEnabled` once you point at this backend. No backend changes needed unless noted.
> Date: 2026-09-10. Repo: `Skyfalll`. Scope: (a) STT/TTS auth fix + (b) new NMT translate path.

---

## 1. Problem → Root Cause → Solution (read this first)

### 1.1 Symptoms
- `POST /voice/chat` or any direct `BhashiniSpeechProvider` use failed at discovery:
  ```json
  {"code": "400 BAD_REQUEST", "message": "ulcaApiKey does not exist. Please provide a valid one."}
  ```
  Surfaced as `503` from `/voice/chat` (retry wrapper re-raises `HTTPStatusError`) or `ValueError` for missing creds.
- Earlier history: on 2026-09-07 `USER_ID + INFERENCE_KEY` authenticated (got pipeline-scoped error, not auth error); by 2026-09-08 spec it failed with `ulcaApiKey does not exist`. The key material rotated into two distinct secrets and the code still sent one as the other.

### 1.2 Root cause (two conflated secrets)
Bhashini ULCA is a **two-step** flow:
1. **Discovery** `POST https://meity-auth.ulcacontrib.org/ulca/apis/v0/model/getModelsPipeline`
   Headers: `userID: <BHASHINI_USER_ID>` + `ulcaApiKey: <BHASHINI_API_KEY>` (short UUID format).
   Body: `{"pipelineTasks": [{"taskType": "asr|tts|translation", "config": {"language": {...}}}], "pipelineRequestConfig": {"pipelineId": "..."}}`.
2. **Compute** `POST <callbackUrl from discovery>` (usually `https://dhruva-api.bhashini.gov.in/services/inference/pipeline`)
   Header: **dynamic** `<inferenceApiKey.name>: <inferenceApiKey.value>` from the discovery response (usually `Authorization: pI7E9...`).

Old `backend/app/providers/bhashini.py:75` sent `self._inference_key` (Dhruva token `pI7E9...`) as `ulcaApiKey` → gateway `400`. Additionally `backend/app/config.py` had no `bhashini_api_key` field, so a correct `BHASHINI_API_KEY` in `.env` was discarded by Pydantic (`extra="ignore"`). Live probe 2026-09-10 proved the split: discovery with `1160f...` → `200`, and returned `inferenceApiKey.value` **exactly equals** `BHASHINI_INFERENCE_KEY=pI7E9...`.

### 1.3 Fix applied (this worktree)
- Canonical `BHASHINI_API_KEY` (+ legacy alias `BHASHINI_UDYAT_KEY`, same value) for discovery; `BHASHINI_INFERENCE_KEY` kept as compute-token fallback only.
- Default `BHASHINI_PIPELINE_ID=64392f96daac500b55c543cd` (MeitY public multitask ASR+NMT+TTS). Previous custom `660fa5bec7fb5b0328229016` kept as commented alternate in `.env`.
- New deterministic NMT path: `translate(text, src, tgt)` + `GET /translate` + `translate_text` chat tool. Chat reasoning stays on Gemini/Anthropic LLM.

### 1.4 NMT vs LLM rule (app policy)
- **NMT (IndicTrans2):** exact strings where numbers/units must not drift — alert banners, advisory sentences, UI labels, speech-to-speech legs. Literal, cheap, terminology-stable, 22 scheduled + English.
- **LLM (Gemini 2.5 Flash / Claude):** free-form chat, explanations, code-mix. Fluent but paraphrases; weak on low-resource scripts (Bodo, Dogri, Santali-Ol Chiki, Manipuri-Meitei, Sindhi, Kashmiri variants).

---

## 2. Every Backend Change (file-by-file)

### 2.1 `backend/app/config.py`
```python
bhashini_user_id: str | None = None
bhashini_api_key: str | None = None          # NEW canonical
bhashini_udyat_key: str | None = None        # NEW legacy alias (UDYAT = ULCA dashboard name)
bhashini_inference_key: str | None = None    # Dhruva compute token (unchanged meaning)
bhashini_pipeline_id: str | None = "64392f96daac500b55c543cd"  # CHANGED was None
```
Env mapping: `BHASHINI_API_KEY`, `BHASHINI_UDYAT_KEY`, `BHASHINI_INFERENCE_KEY`, `BHASHINI_PIPELINE_ID`. Resolution order in provider: explicit ctor args > `API_KEY` > `UDYAT_KEY` > `INFERENCE_KEY` (last with `logger.warning`).

### 2.2 `backend/app/providers/bhashini.py` (rewritten, 230 lines)
- `__init__(user_id=None, api_key=None, inference_key=None, pipeline_id=None, discovery_url=..., client=None)`. **New `api_key` param.**
- Validation: `if not user_id or not api_key: raise ValueError("BHASHINI_USER_ID and BHASHINI_API_KEY (legacy alias BHASHINI_UDYAT_KEY also accepted) must both be set ... NOTE: BHASHINI_INFERENCE_KEY is the Dhruva compute token, not the ULCA API key ...")`.
- `_discover(task_type, language, target_language=None)`:
  - `translation` includes `{"sourceLanguage": lang, "targetLanguage": target}`; `asr`/`tts` only `sourceLanguage`.
  - Headers now `{"userID": self._user_id, "ulcaApiKey": self._api_key, ...}` (was `self._inference_key`).
  - Response parse defensive: `endpoint.get("inferenceApiKey")` dict-check, default name `"Authorization"`, value fallback `self._inference_key`. Old code `endpoint["inferenceApiKey"]["name/value"]` would `KeyError`.
- `transcribe(audio_base64, audio_format, language, sampling_rate=16000)` — unchanged wire shape.
- `synthesize(text, language)` — unchanged wire shape.
- **NEW** `translate(text, source_language, target_language) -> TranslationResult`:
  ```json
  // compute request
  {"pipelineTasks": [{"taskType": "translation", "config": {"language": {"sourceLanguage": "en", "targetLanguage": "hi"}, "serviceId": "<from discovery>"}}], "inputData": {"input": [{"source": "Heavy rainfall expected"}]}}
  // compute response walk
  payload["pipelineResponse"][0]["output"][0]["target"]  // e.g. "भारी बारिश की संभावना"
  ```

### 2.3 NEW `backend/app/providers/translation.py`
```python
@dataclass TranslationResult(text, source_language, target_language, raw_payload)
class TranslatorProvider(Protocol):
    def translate(self, text, source_language, target_language) -> TranslationResult: ...
```

### 2.4 NEW `backend/app/translation/__init__.py` (empty) + `backend/app/translation/service.py`
```python
def translate_text(text, source_language, target_language, provider=None) -> dict:
    # raises ValueError on empty text/langs; owns+closes self-built provider
    # returns {"translated_text": str, "source_language": str, "target_language": str}
```

### 2.5 `backend/app/main.py`
- Import `TranslatorProvider`, `translate_text`.
- **NEW** `GET /translate?text&source&target` (Query: `text 1-2000`, `source/target 2-10` ISO-639):
  - `200 {"translated_text","source_language","target_language"}`
  - `422` empty text/langs or bad history shape; `502` malformed vendor payload (`KeyError/IndexError`); `503` unconfigured (`ValueError`) or vendor down (`HTTPStatusError/TransportError`).
  - `get_translator_provider()` Depends mirrors `get_stt/tts_provider` (yields `BhashiniSpeechProvider`, closes after request).
- `/voice/*` unchanged except they now authenticate (no route-signature change).

### 2.6 `backend/app/chat/tools.py` — NEW 11th tool
```python
ToolSpec(name="translate_text",
  description="Translate an exact string deterministically via Bhashini NMT ... ISO-639 codes, e.g. source 'en', target 'hi'.",
  input_schema={"type":"object","properties":{"text":{"type":"string"},"source":{"type":"string"},"target":{"type":"string"}},"required":["text","source","target"]})
# handler _handle_translate_text -> translate_text(...); registered in _HANDLERS.
```
System prompt unchanged (tool description carries the when-to-use rule).

### 2.7 `backend/.env.example` + `backend/.env` (gitignored, local only)
`.env.example` now documents `BHASHINI_API_KEY` + `BHASHINI_UDYAT_KEY` alias + `BHASHINI_INFERENCE_KEY` + default `PIPELINE_ID=64392f...`.
Real `.env` set to (values redacted here — see the local, gitignored `backend/.env` for the actual ones):
```
BHASHINI_USER_ID=<redacted>
BHASHINI_API_KEY=<redacted>
BHASHINI_UDYAT_KEY=<redacted, same value as BHASHINI_API_KEY>
BHASHINI_INFERENCE_KEY=<redacted>
BHASHINI_PIPELINE_ID=64392f96daac500b55c543cd
# ALT_PIPELINE_ID=660fa5bec7fb5b0328229016
```
**Security:** the real values above were pasted in plaintext during the fix discussion and briefly lived in this file — **rotate `BHASHINI_API_KEY`/`BHASHINI_UDYAT_KEY` on the ULCA dashboard** (they are the same value) as if they were exposed, since a chat transcript is not a secret store. Never commit `.env`; `.env.example` carries placeholders only. This file is safe to commit now that the values are redacted.

### 2.8 Tests
- `tests/test_bhashini_provider.py`: old discovery/compute/retry/close tests kept (fallback keeps `inference_key="k"` passing as `ulcaApiKey="k"` in mocks); replaced `test_raises_without_pipeline_id` with `test_defaults_to_meity_pipeline_id_when_pipeline_id_not_set`; added `test_raises_without_api_key`, `test_prefers_api_key_for_ulca_header_over_inference_key`, `test_udyat_key_alias_used_when_api_key_missing`, `test_translate_sends_source_and_target_and_parses_target`, `test_translate_falls_back_to_inference_key_when_discovery_omits_value`.
- NEW `tests/test_translate_endpoint.py`: `GET /translate` happy path via `dependency_overrides`, empty-text rejection, service validation.
- `tests/test_voice_endpoint.py`: 503 test now also blanks `API_KEY`/`UDYAT_KEY`.
- `tests/test_chat_tools.py`: expected tool set now 11 names (added `translate_text`).
- Result: `61 passed` (`test_bhashini + test_translate + test_voice + test_chat_tools + test_chat_service`).
- Live (2026-09-10, 2 calls, rate limit ~50/hr): discovery `200 {pipelineResponseConfig:[translation×1], callbackUrl: dhruva-..., auth Authorization, value==INFERENCE_KEY}`; `translate_text("Heavy rainfall expected","en","hi")` → `{"translated_text": "भारी बारिश की संभावना", ...}`.

---

## 3. API Contracts for Flutter (copy these)

Base URL: `AppEnv.apiBaseUrl` (emulator `http://10.0.2.2:8000`, device LAN IP, web `127.0.0.1:8000`).

### 3.1 `GET /translate` (NEW — deterministic NMT)
```
GET /translate?text=Heavy%20rainfall%20expected&source=en&target=hi
→ 200 {"translated_text": "भारी बारिश की संभावना", "source_language": "en", "target_language": "hi"}
→ 422 {"detail": "text must be a non-empty string"} (also on missing src/tgt)
→ 503 {"detail": "BHASHINI_USER_ID and BHASHINI_API_KEY ..."} | {"detail": "The translation provider is temporarily unavailable..."}
→ 502 {"detail": "The translation provider returned an invalid response..."}
```
Notes: `text` max 2000 chars (chunk longer advisories client-side on sentence boundaries); `raw_payload` never exposed; no auth header needed on this app backend (internal `X-Internal-API-Key` only guards `/internal/ingest/*`).

### 3.2 `GET /voice/languages` (unchanged)
```
→ 200 {"languages": [{"code":"as","name":"Assamese"},{...23 total...}], "count": 23}
```
Codes: `as bn brx doi en gom gu hi kn ks mai ml mni mr ne or pa sa sat sd ta te ur`.

### 3.3 `POST /voice/chat` (unchanged shape, now authenticates)
```
multipart/form-data: audio: <test.wav WAV only> (≤10MB), language: "hi" (Form), history: "<json.dumps([...])>" (optional Form string)
→ 200 {"transcript": "मुंबई में मौसम कैसा है", "reply_text": "...", "reply_audio_base64": "<wav b64>", "history": [...]}
→ 422 bad WAV / bad history JSON / non-wav upload; 413 >10MB; 502 malformed vendor payload; 503 voice/LLM down or unconfigured
```
Critical: send the **real** WAV sampling rate — `_require_wav_upload` parses it via `wave.open().getframerate()` and forwards as `samplingRate`. Wrong rate silently garbles transcript (no loud error). WAV-only in V1 (no webm/mp3 transcode).

### 3.4 `POST /chat` + `translate_text` tool (unchanged shape, 1 new tool)
`POST /chat {"message": str(1-2000), "history": [...]|null} → {"reply","history"}`. The LLM may now call `translate_text {text, source, target}` for literal strings; `ChatTurn.tryFromRaw` already drops `tool/tool_calls/blank` turns — no change needed, but keep that filter.

### 3.5 Language coverage (pipeline `64392f...`)
ASR+NMT+TTS across 22 scheduled + English. ISO-639 app codes used by backend: `as bn brx doi en gom gu hi kn ks mai ml mni mr ne or pa sa sat sd ta te ur`. NMT model family: IndicTrans2 (BPCC, IN22 benchmark). TTS `gender: female`, output `wav` b64. If a pair returns empty/no config, surface "translation not available for this pair" (don't retry-loop — burns the ~50/hr quota).

---

## 4. Flutter Wiring Guide (for Claude)

### 4.1 New file `lib/data/translate_api.dart`
```dart
class TranslationResult { final String translatedText, sourceLanguage, targetLanguage; ... }
class TranslateApi {
  TranslateApi(this._dio); final Dio _dio;
  Future<TranslationResult> translate({required String text, required String source, required String target}) =>
    guardApi(() async {
      final res = await _dio.get('/translate', queryParameters: {'text': text, 'source': source, 'target': target});
      final b = res.data as Map<String,dynamic>;
      return TranslationResult(translatedText: b['translated_text'] as String, ...);
    });
}
final translateApiProvider = Provider((ref) => TranslateApi(ref.watch(apiClientProvider)));
```
Mirror `lib/data/weather_api.dart` (`guardApi` + `AppError` mapping). `404` → treat as unavailable (like `geocoding_api`); `503` → "voice/translation warming up" snackbar, not crash. Chunk `text >1500 chars` on `।|.|!|?` boundaries, translate pieces, join with original separators (numbers/units preserved by NMT — assert in widget test with `64.5mm`).

### 4.2 Where to call what
- Alert banners (`AlertBanner`), advisory lists (`advisory_screen`), marine zone sheets: NMT via `TranslateApi` (exact). Cache per `(text,src,tgt)` in-memory `Map` (no backend cache exists by design).
- Chat transcript (`AssistantMessage`): leave LLM-verbalized (fluent). Optional "Translate" `⋮` menu item per bubble → `TranslateApi` on demand.
- Voice: reuse existing `ChatComposer` mic → `POST /voice/chat`; no new endpoint. After backend fix, remove `kVoiceEnabled` gate only (see §4.4).

### 4.3 Riverpod + tests (mirror existing patterns)
- `translateControllerProvider` as `Notifier<AsyncValue<TranslationResult?>>` with `translate()`/`retry()`, or simpler: `FutureProvider.family<TranslationResult,(text,src,tgt)>` for labels.
- Tests: `test/data/translate_api_test.dart` (mock Dio: 200/422/503 mapping, `translated_text` parse); widget test that `64.5 mm` survives `en→hi`; golden update not needed unless UI changes.
- Keep `ChatTurn.tryFromRaw` filter — new tool adds more `tool` history entries.

### 4.4 Unhide voice checklist
1. Point `API_BASE_URL` at this backend; `GET /translate?text=hi&source=en&target=hi` → 200.
2. Remove `kVoiceEnabled` gate on mic button + `/voice/chat` path (per `2026-09-08-flutter-frontend-design.md §9`).
3. Manual: Hindi WAV 16kHz → transcript → reply → WAV plays; `samplingRate` = real file rate.
4. `flutter test` + `--update-goldens` only if UI changed; eye-check day/night goldens.

### 4.5 Pitfalls (from backend scars)
- Never send `INFERENCE_KEY` as `ulcaApiKey` — that was the whole outage. Frontend never handles either key (backend-only).
- Don't hammer: BHASHINI ~50 req/hr. Debounce translate-on-type; translate on submit/expand only.
- WAV-only; `audio/mpeg` → `422`. `>10MB` → `413`.
- NMT `target` walk is `output[0].target` (not `source` like ASR) — backend handles it; if you add direct Dhruva calls later, don't reuse the ASR parser.

---

## 5. Verification Log (backend, this worktree)
- `pytest tests/test_bhashini_provider.py tests/test_translate_endpoint.py tests/test_voice_endpoint.py tests/test_chat_tools.py tests/test_chat_service.py` → **61 passed**.
- Live discovery `translation en→hi` → `200`, `tasks:[(translation,1)]`, `callback: https://dhruva-api.bhashini.gov.in/services/inference/pipeline`, `auth: Authorization`, `value==INFERENCE_KEY: True`.
- Live `translate_text("Heavy rainfall expected","en","hi")` → `भारी बारिश की संभावना`.
- Files touched: `app/config.py`, `app/providers/bhashini.py`, `app/providers/translation.py` (new), `app/translation/__init__.py` + `service.py` (new), `app/main.py` (`/translate`), `app/chat/tools.py` (`translate_text` tool), `tests/test_bhashini_provider.py`, `tests/test_translate_endpoint.py` (new), `tests/test_voice_endpoint.py`, `tests/test_chat_tools.py`, `.env.example`, `.env` (local, gitignored).

## 6. Open Items for Frontend Agent
- [ ] Add `TranslateApi` + provider + unit tests (§4.1/4.3).
- [ ] Wire NMT into alert/advisory/zone strings with per-string cache; keep chat on LLM.
- [ ] Optional per-bubble "Translate" menu.
- [ ] Remove `kVoiceEnabled` gate after pointing at fixed backend; manual Hindi + English round-trip.
- [ ] Rotate ULCA `BHASHINI_API_KEY` post-merge (was pasted in chat); update server `.env` only.
