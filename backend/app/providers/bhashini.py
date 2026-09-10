"""BHASHINI (ULCA) speech-to-text/text-to-speech/translation adapter.

BHASHINI's API is a two-step flow, unlike every other provider in this
codebase: a "pipeline config" discovery call returns a compute endpoint
URL (callbackUrl) AND an auth header — both its NAME and its VALUE — that
must be used for the second "pipeline compute" call, which does the actual
work. The header name is not fixed (never hardcode it); it comes back in
the discovery response every time.

Credential model (fixed 2026-09-10 after `400 ulcaApiKey does not exist`):
- discovery header `ulcaApiKey` = ULCA API key (`BHASHINI_API_KEY`,
  legacy alias `BHASHINI_UDYAT_KEY`). Short UUID format.
- compute header `<dynamic name>` (usually `Authorization`) = Dhruva token
  (`BHASHINI_INFERENCE_KEY`, long opaque like `pI7E9...`), normally read
  from `pipelineInferenceAPIEndPoint.inferenceApiKey` in the discovery
  response. Never send the Dhruva token as `ulcaApiKey`.
- `BHASHINI_PIPELINE_ID` defaults to MeitY's public multitask pipeline
  `64392f96daac500b55c543cd` (ASR+NMT+TTS, 22 scheduled languages +
  English). Shared catalogue entry, not a per-user secret.

Never wrapped in a cache (see app/chat/service.py's docstring for the
general principle) — a transcription/synthesis/translation result is
specific to one utterance, there's nothing meaningful to cache it against.
"""

import logging
from dataclasses import dataclass

import httpx

from app.config import get_settings
from app.providers.retry import call_with_retries
from app.providers.speech import SynthesisResult, TranscriptionResult
from app.providers.translation import TranslationResult

logger = logging.getLogger(__name__)

BHASHINI_DISCOVERY_URL = "https://meity-auth.ulcacontrib.org/ulca/apis/v0/model/getModelsPipeline"

# MeitY public multitask pipeline (ASR+NMT+TTS). Mirrors Settings default so
# explicit constructor callers without a pipeline_id get the same value.
_MEITY_PIPELINE_ID = "64392f96daac500b55c543cd"

_TTS_OUTPUT_AUDIO_FORMAT = "wav"
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
        api_key: str | None = None,
        inference_key: str | None = None,
        pipeline_id: str | None = None,
        discovery_url: str = BHASHINI_DISCOVERY_URL,
        client: httpx.Client | None = None,
    ):
        settings = get_settings()
        self._user_id = user_id if user_id is not None else settings.bhashini_user_id
        # Canonical key first, legacy UDYAT alias second, Dhruva token last
        # (last resort keeps old single-key .env files working but logs a
        # warning since it re-sends the compute token as ulcaApiKey).
        settings_api = (
            settings.bhashini_api_key
            or getattr(settings, "bhashini_udyat_key", None)
            or settings.bhashini_inference_key
        )
        if api_key is not None or inference_key is not None:
            self._api_key = api_key if api_key is not None else inference_key
            self._inference_key = inference_key if inference_key is not None else api_key
        else:
            self._api_key = settings_api
            self._inference_key = settings.bhashini_inference_key or settings.bhashini_api_key

        self._pipeline_id = (
            pipeline_id
            if pipeline_id is not None
            else (settings.bhashini_pipeline_id or _MEITY_PIPELINE_ID)
        )

        if not self._user_id or not self._api_key:
            raise ValueError(
                "BHASHINI_USER_ID and BHASHINI_API_KEY (legacy alias "
                "BHASHINI_UDYAT_KEY also accepted) must both be set. "
                "Set them in backend/.env or as environment variables to enable voice. "
                "NOTE: BHASHINI_INFERENCE_KEY is the Dhruva compute token, not the "
                "ULCA API key — sending it as `ulcaApiKey` yields "
                "`400 ulcaApiKey does not exist`."
            )

        if (
            inference_key is None
            and api_key is None
            and settings.bhashini_api_key is None
            and getattr(settings, "bhashini_udyat_key", None) is None
            and settings.bhashini_inference_key
        ):
            logger.warning(
                "BhashiniSpeechProvider falling back to BHASHINI_INFERENCE_KEY as "
                "ulcaApiKey. This preserves backward compatibility but will fail "
                "with `400 ulcaApiKey does not exist` if the value is a Dhruva "
                "compute token — set BHASHINI_API_KEY from the ULCA dashboard."
            )

        self._discovery_url = discovery_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=30.0)

    def _discover(
        self, task_type: str, language: str, target_language: str | None = None
    ) -> _PipelineConfig:
        lang_cfg: dict = {"sourceLanguage": language}
        if task_type == "translation" and target_language:
            lang_cfg["targetLanguage"] = target_language
        response = call_with_retries(
            lambda: self._client.post(
                self._discovery_url,
                headers={
                    "userID": self._user_id,
                    "ulcaApiKey": self._api_key,
                    "Content-Type": "application/json",
                },
                json={
                    "pipelineTasks": [
                        {"taskType": task_type, "config": {"language": lang_cfg}}
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
        inference_key = endpoint.get("inferenceApiKey") if isinstance(endpoint, dict) else None
        if isinstance(inference_key, dict):
            auth_header_name = inference_key.get("name") or "Authorization"
            auth_header_value = inference_key.get("value") or self._inference_key
        else:
            auth_header_name = "Authorization"
            auth_header_value = self._inference_key
        return _PipelineConfig(
            callback_url=endpoint["callbackUrl"],
            auth_header_name=auth_header_name,
            auth_header_value=auth_header_value,
            service_id=task_config["serviceId"],
        )

    def transcribe(
        self,
        audio_base64: str,
        audio_format: str,
        language: str,
        sampling_rate: int = _ASR_SAMPLING_RATE,
    ) -> TranscriptionResult:
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
                                # The REAL sampling rate of the supplied audio.
                                # Sending a wrong rate here does not fail loudly —
                                # BHASHINI resamples against the number it is
                                # told, so a mismatch silently degrades (or
                                # garbles) the transcript instead of erroring.
                                "samplingRate": sampling_rate,
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
        return SynthesisResult(audio_base64=audio_content, audio_format=_TTS_OUTPUT_AUDIO_FORMAT, raw_payload=payload)

    def translate(self, text: str, source_language: str, target_language: str) -> TranslationResult:
        """Deterministic text translation via pipeline NMT (IndicTrans2).

        Unlike LLM translation (paraphrases, may drift numbers/units), NMT is
        literal and terminology-stable — use for alert/advisory/UI strings.
        """
        config = self._discover("translation", source_language, target_language)
        response = call_with_retries(
            lambda: self._client.post(
                config.callback_url,
                headers={config.auth_header_name: config.auth_header_value, "Content-Type": "application/json"},
                json={
                    "pipelineTasks": [
                        {
                            "taskType": "translation",
                            "config": {
                                "language": {
                                    "sourceLanguage": source_language,
                                    "targetLanguage": target_language,
                                },
                                "serviceId": config.service_id,
                            },
                        }
                    ],
                    "inputData": {"input": [{"source": text}]},
                },
            )
        )
        payload = response.json()
        translated = payload["pipelineResponse"][0]["output"][0]["target"]
        return TranslationResult(
            text=translated,
            source_language=source_language,
            target_language=target_language,
            raw_payload=payload,
        )

    def close(self) -> None:
        if self._owns_client:
            self._client.close()
