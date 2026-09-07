import json

import httpx
import pytest

from app.config import get_settings
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


# An omitted argument falls back to Settings, and backend/.env carries real
# BHASHINI credentials on dev machines — so these two tests must explicitly
# blank the environment rather than trusting ambient state, exactly as
# test_anthropic_llm_provider.py does for ANTHROPIC_API_KEY. An
# empty-but-present env var beats pydantic-settings' dotenv fallback, which a
# plain monkeypatch.delenv would not.
def test_raises_without_credentials(monkeypatch):
    monkeypatch.setenv("BHASHINI_USER_ID", "")
    get_settings.cache_clear()
    try:
        with pytest.raises(ValueError, match="BHASHINI_USER_ID"):
            BhashiniSpeechProvider(user_id=None, inference_key="k", pipeline_id="p")
    finally:
        get_settings.cache_clear()


def test_raises_without_pipeline_id(monkeypatch):
    monkeypatch.setenv("BHASHINI_PIPELINE_ID", "")
    get_settings.cache_clear()
    try:
        with pytest.raises(ValueError, match="BHASHINI_PIPELINE_ID"):
            BhashiniSpeechProvider(user_id="u", inference_key="k", pipeline_id=None)
    finally:
        get_settings.cache_clear()


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
