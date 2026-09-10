import asyncio
import base64
import io
import json
import logging
import wave
from collections.abc import Generator
from contextlib import asynccontextmanager
from dataclasses import dataclass

import httpx
from fastapi import (
    Depends,
    FastAPI,
    File,
    Form,
    Header,
    HTTPException,
    Query,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from app.aviation.service import get_metar
from app.chat.service import chat_turn
from app.config import get_settings
from app.db import check_db_connection
from app.air_quality.service import get_air_quality
from app.forecast.service import get_forecast
from app.geocoding.service import geocode_place, reverse_geocode_point
from app.history.service import get_historical_weather, list_available_history
from app.ingestion.alerts import ingest_alerts
from app.ingestion.gfs import ingest_gfs_forecast
from app.ingestion.marine import ingest_pfz_zones
from app.marine import service as marine_service
from app.nwp.service import get_nwp_forecast
from app.providers.bhashini import BhashiniSpeechProvider
from app.providers.factory import build_llm_provider
from app.providers.incois import INCOISMarineProvider
from app.providers.llm import LLMProvider
from app.providers.sachet import SACHETWarningProvider
from app.providers.speech import SpeechToTextProvider, TextToSpeechProvider
from app.realtime.manager import connection_manager, make_new_alerts_broadcaster
from app.scheduler import IngestionScheduler
from app.skills.agriculture import get_agriculture_advisory
from app.skills.urban import get_urban_advisory
from app.voice.service import voice_chat
from app.warning import service as warning_service
from app.weather.service import get_weather

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Must be an ASYNC context manager — Starlette's lifespan= parameter
    # calls `async with lifespan_context(app)`, and a plain @contextmanager
    # fails immediately (verified directly: "TypeError: '_GeneratorContextManager'
    # object does not support the asynchronous context manager protocol").
    # The body itself has nothing to await — IngestionScheduler.start()/stop()
    # are synchronous, thread-based calls — but that doesn't change which
    # protocol the object itself must implement.
    settings = get_settings()
    scheduler = IngestionScheduler()
    app.state.broadcast_new_alerts = make_new_alerts_broadcaster(asyncio.get_running_loop())
    if settings.enable_scheduler:
        scheduler.start(
            [
                (
                    "alerts",
                    lambda: ingest_alerts(
                        SACHETWarningProvider(), on_new_alerts=app.state.broadcast_new_alerts
                    ),
                    settings.alert_ingestion_interval_seconds,
                ),
                (
                    "marine",
                    lambda: ingest_pfz_zones(INCOISMarineProvider()),
                    settings.marine_ingestion_interval_seconds,
                ),
                (
                    "gfs",
                    lambda: ingest_gfs_forecast(),
                    settings.gfs_ingestion_interval_seconds,
                ),
            ]
        )
    yield
    if settings.enable_scheduler:
        scheduler.stop()


app = FastAPI(title="WeatherGPT Backend", lifespan=lifespan)

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


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/health/db")
def health_db() -> dict[str, str]:
    check_db_connection()
    return {"status": "ok", "db": "connected"}


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


@app.post("/internal/ingest/alerts", dependencies=[Depends(verify_internal_api_key)])
def trigger_alert_ingestion() -> dict[str, int]:
    count = ingest_alerts(
        SACHETWarningProvider(), on_new_alerts=getattr(app.state, "broadcast_new_alerts", None)
    )
    return {"ingested": count}


@app.get("/alerts")
def list_alerts() -> list[dict]:
    return warning_service.list_alerts()


@app.websocket("/ws/alerts")
async def alerts_websocket(websocket: WebSocket) -> None:
    await connection_manager.connect(websocket)
    try:
        while True:
            # receive(), not receive_text(): this endpoint is push-only and
            # ignores whatever the client sends — it reads solely to detect
            # disconnection — while receive_text() assumes every frame is
            # text and raises KeyError('text') on a BINARY frame. That
            # KeyError is not a WebSocketDisconnect, so it would escape the
            # handler into the ASGI server and close the connection with
            # error code 1011. receive() is frame-type agnostic.
            #
            # The explicit disconnect check is REQUIRED, not belt-and-braces:
            # unlike receive_text(), the raw receive() does not raise
            # WebSocketDisconnect — it RETURNS the "websocket.disconnect"
            # message and flips the socket to DISCONNECTED, so looping around
            # to call it again raises RuntimeError('Cannot call "receive"
            # once a disconnect message has been received.'), which this
            # except clause would not catch either. (Verified empirically:
            # without this break, all four tests in
            # tests/test_alerts_websocket.py fail with exactly that error.)
            message = await websocket.receive()
            if message["type"] == "websocket.disconnect":
                break
    except WebSocketDisconnect:
        pass
    finally:
        connection_manager.disconnect(websocket)


@app.get("/weather")
def get_weather_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
) -> dict:
    return get_weather(lat, lon)


@app.get("/air-quality")
def get_air_quality_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
) -> dict:
    return get_air_quality(lat, lon)


@app.get("/forecast")
def get_forecast_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    days: int = Query(5, ge=1, le=16),
) -> list[dict]:
    return get_forecast(lat, lon, days)


@app.get("/geocode")
def geocode_endpoint(q: str = Query(..., min_length=1)) -> dict:
    result = geocode_place(q)
    if result is None:
        raise HTTPException(status_code=404, detail="Location not found")
    return result


@app.get("/reverse-geocode")
def reverse_geocode_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
) -> dict:
    """Name a coordinate, for showing the device's own location on Home.

    404 (not 500) when the point has no place name — mid-ocean
    coordinates legitimately have none, and the client treats that as
    "unnamed location" rather than as a failure. Mirrors /geocode.
    """
    result = reverse_geocode_point(lat, lon)
    if result is None:
        raise HTTPException(status_code=404, detail="Location not found")
    return result


@app.get("/metar")
def get_metar_endpoint(
    icao: str = Query(..., min_length=4, max_length=4, pattern="^[A-Za-z]{4}$")
) -> dict:
    result = get_metar(icao)
    if result is None:
        raise HTTPException(status_code=404, detail="No METAR data for this station")
    return result


@app.get("/advisory/agriculture")
def agriculture_advisory_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    crop: str | None = Query(None),
    days: int = Query(5, ge=1, le=16),
) -> dict:
    return get_agriculture_advisory(lat, lon, crop=crop, days=days)


@app.get("/advisory/urban")
def urban_advisory_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    days: int = Query(5, ge=1, le=16),
) -> dict:
    return get_urban_advisory(lat, lon, days=days)


@app.post("/internal/ingest/marine", dependencies=[Depends(verify_internal_api_key)])
def trigger_marine_ingestion() -> dict[str, int]:
    count = ingest_pfz_zones(INCOISMarineProvider())
    return {"ingested": count}


@app.get("/marine/pfz-zones")
def list_pfz_zones() -> list[dict]:
    # geometry is deliberately included (it's substantive content here, not internal bookkeeping like raw_payload).
    return marine_service.list_pfz_zones()


@app.post("/internal/ingest/gfs", dependencies=[Depends(verify_internal_api_key)])
def trigger_gfs_ingestion() -> dict[str, int]:
    count = ingest_gfs_forecast()
    return {"ingested": count}


@app.get("/nwp")
def nwp_forecast_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
) -> list[dict]:
    return get_nwp_forecast(lat, lon)


@app.get("/historical/available")
def historical_available_endpoint() -> list[dict]:
    """What the historical dataset actually covers.

    `/historical` matches an exact location name and date against a small
    fixed seed matrix, so without this a client can only guess and collect
    404s. Declared BEFORE `/historical` so the literal path is matched
    first — FastAPI resolves in declaration order.
    """
    return list_available_history()


@app.get("/historical")
def historical_weather_endpoint(
    location: str = Query(..., min_length=1),
    date: str = Query(..., pattern=r"^\d{4}-\d{2}-\d{2}$"),
) -> dict:
    result = get_historical_weather(location, date)
    if result is None:
        raise HTTPException(
            status_code=404,
            detail=(
                f"No historical data for '{location}' on {date}. This dataset only covers "
                "a small pre-seeded set of major Indian cities and sample dates — see "
                "backend/scripts/seed_era5_history.py's LOCATIONS/DATES for exact coverage."
            ),
        )
    return result


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    history: list[dict] | None = None


# Unlike every other route in this file, chat_turn has no cache to fall back to in
# tests — every other route's service only reaches its provider on a cache miss, so
# seeding Postgres keeps tests offline; chat has no such cache, so a real Depends
# seam is needed here to override the LLM provider in tests.
#
# This is a generator dependency so FastAPI's Depends lifecycle closes the
# provider after the request completes. chat_turn() only closes a provider it
# constructs itself (see its docstring/comment) — since the endpoint always
# passes this Depends-provided instance in as an explicit `provider` argument,
# chat_turn treats it as injected and never closes it, so closing here is the
# only place this instance gets cleaned up.
def get_llm_provider() -> Generator[LLMProvider, None, None]:
    try:
        provider = build_llm_provider()
    except ValueError as e:
        raise HTTPException(status_code=503, detail=str(e)) from e
    try:
        yield provider
    finally:
        provider.close()


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


# 10 MB — generous headroom for a 16kHz mono 16-bit WAV of several minutes
# (~32 KB/s, so ~5 minutes), while still bounding how much a single request can
# make the process read into memory and base64-encode.
_MAX_AUDIO_UPLOAD_BYTES = 10 * 1024 * 1024


@dataclass
class _ValidatedAudio:
    """What _require_wav_upload hands the endpoint.

    A single Depends can only return one value, and the endpoint needs BOTH the
    audio bytes and the sampling rate parsed out of them — hence a small
    dataclass rather than returning the UploadFile and re-reading/reparsing it
    in the endpoint body.
    """

    content: bytes
    sampling_rate: int


def _require_wav_upload(audio: UploadFile = File(...)) -> _ValidatedAudio:
    # A dedicated Depends (rather than a check in the endpoint body) so this
    # validation runs, and can reject the request, before the get_stt_provider/
    # get_tts_provider dependencies below are even evaluated — otherwise a bad
    # upload would surface as a 503 (BHASHINI not configured) instead of a 422,
    # since FastAPI only calls the endpoint body after every Depends succeeds.
    if not (audio.content_type or "").endswith("wav") and not audio.filename.lower().endswith(".wav"):
        raise HTTPException(
            status_code=422,
            detail="Only WAV audio is supported in this version. Convert your audio to WAV before uploading.",
        )

    # Checked BEFORE .read() — the point of a size limit is to avoid pulling an
    # arbitrarily large body into memory, which reading first would defeat.
    if audio.size is not None and audio.size > _MAX_AUDIO_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Audio file too large. Maximum size is 10MB.")

    content = audio.file.read()
    try:
        with wave.open(io.BytesIO(content), "rb") as wav_file:
            sampling_rate = wav_file.getframerate()
    except (wave.Error, EOFError) as e:
        # The filename/content-type check above is only a client-supplied hint;
        # bytes that don't actually parse as RIFF/WAVE are the client's problem,
        # so 422 rather than letting it explode as a 500 later.
        raise HTTPException(status_code=422, detail="Uploaded file is not a valid WAV file.") from e

    return _ValidatedAudio(content=content, sampling_rate=sampling_rate)


@app.post("/voice/chat")
def voice_chat_endpoint(
    validated_audio: _ValidatedAudio = Depends(_require_wav_upload),
    language: str = Form("hi"),
    # Multipart form fields are strings, so history arrives JSON-encoded
    # (json.dumps([...]) on the client) rather than as a parsed list the way
    # /chat's JSON body delivers it.
    history: str | None = Form(None),
    stt: SpeechToTextProvider = Depends(get_stt_provider),
    tts: TextToSpeechProvider = Depends(get_tts_provider),
    llm: LLMProvider = Depends(get_llm_provider),
) -> dict:
    # Deliberately a SEPARATE try/except from the voice_chat() call below: a
    # client sending unparseable history JSON (422) and BHASHINI returning a
    # malformed payload (502) are different faults, and folding them together
    # would misattribute one as the other.
    parsed_history = None
    if history is not None:
        try:
            parsed_history = json.loads(history)
        except json.JSONDecodeError as e:
            raise HTTPException(status_code=422, detail=f"Invalid history: {e}") from e

    audio_base64 = base64.b64encode(validated_audio.content).decode("ascii")
    try:
        return voice_chat(
            audio_base64=audio_base64,
            audio_format="wav",
            language=language,
            history=parsed_history,
            sampling_rate=validated_audio.sampling_rate,
            stt_provider=stt,
            tts_provider=tts,
            # voice_chat's default chat_fn is chat_turn with no provider, which
            # would build its own live LLM provider — bypassing the Depends seam
            # entirely. Binding the Depends-provided `llm` here keeps /voice/chat
            # consistent with /chat: both route through the same overridable
            # get_llm_provider dependency, so tests can fake the LLM for either.
            chat_fn=lambda message, history: chat_turn(message, history, provider=llm),
        )
    except (KeyError, IndexError) as e:
        # A malformed or truncated BHASHINI payload — e.g. the
        # payload["pipelineResponse"][0]["output"][0]["source"] walk in
        # BhashiniSpeechProvider.transcribe failing. The vendor's fault, not the
        # client's, so 502 rather than 422.
        raise HTTPException(
            status_code=502, detail="The voice provider returned an invalid response. Please try again."
        ) from e
    except (httpx.HTTPStatusError, httpx.TransportError) as e:
        # A transient failure that survived retry (see app/providers/retry.py,
        # already wired into BhashiniSpeechProvider), or a non-retryable
        # vendor-side error. Clean 503 instead of FastAPI's opaque default 500,
        # without leaking the vendor's raw exception text to the client.
        raise HTTPException(
            status_code=503, detail="The voice provider is temporarily unavailable. Please try again shortly."
        ) from e
