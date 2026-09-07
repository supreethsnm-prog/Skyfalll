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

from dataclasses import dataclass

import httpx

from app.config import get_settings
from app.providers.retry import call_with_retries
from app.providers.speech import SynthesisResult, TranscriptionResult

BHASHINI_DISCOVERY_URL = "https://meity-auth.ulcacontrib.org/ulca/apis/v0/model/getModelsPipeline"

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
        return SynthesisResult(audio_base64=audio_content, audio_format=_TTS_OUTPUT_AUDIO_FORMAT, raw_payload=payload)

    def close(self) -> None:
        if self._owns_client:
            self._client.close()
