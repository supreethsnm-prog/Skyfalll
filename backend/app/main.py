from collections.abc import Generator

from fastapi import Depends, FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

from app.aviation.service import get_metar
from app.chat.service import chat_turn
from app.db import check_db_connection
from app.geocoding.service import geocode_place
from app.ingestion.alerts import ingest_alerts
from app.ingestion.marine import ingest_pfz_zones
from app.marine import service as marine_service
from app.providers.anthropic import AnthropicLLMProvider
from app.providers.incois import INCOISMarineProvider
from app.providers.llm import LLMProvider
from app.providers.sachet import SACHETWarningProvider
from app.warning import service as warning_service
from app.weather.service import get_weather

app = FastAPI(title="WeatherGPT Backend")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/health/db")
def health_db() -> dict[str, str]:
    check_db_connection()
    return {"status": "ok", "db": "connected"}


@app.post("/internal/ingest/alerts")
def trigger_alert_ingestion() -> dict[str, int]:
    count = ingest_alerts(SACHETWarningProvider())
    return {"ingested": count}


@app.get("/alerts")
def list_alerts() -> list[dict]:
    return warning_service.list_alerts()


@app.get("/weather")
def get_weather_endpoint(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
) -> dict:
    return get_weather(lat, lon)


@app.get("/geocode")
def geocode_endpoint(q: str = Query(..., min_length=1)) -> dict:
    result = geocode_place(q)
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


@app.post("/internal/ingest/marine")
def trigger_marine_ingestion() -> dict[str, int]:
    count = ingest_pfz_zones(INCOISMarineProvider())
    return {"ingested": count}


@app.get("/marine/pfz-zones")
def list_pfz_zones() -> list[dict]:
    # geometry is deliberately included (it's substantive content here, not internal bookkeeping like raw_payload).
    return marine_service.list_pfz_zones()


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
        provider = AnthropicLLMProvider()
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
    except (KeyError, ValueError) as e:
        raise HTTPException(status_code=422, detail=f"Invalid history: {e}") from e
