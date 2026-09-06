from datetime import datetime, timezone

from sqlalchemy import insert

from app.chat.service import chat_turn
from app.db import get_engine
from app.models import WeatherReading
from app.providers.llm import LLMTurn, ToolCall
from tests.conftest import FakeLLMProvider


def _seed_weather():
    with get_engine().begin() as conn:
        conn.execute(
            insert(WeatherReading).values(
                latitude=19.08,
                longitude=72.88,
                temperature_c=28.0,
                humidity_pct=70,
                weather_code=1,
                wind_speed_kmh=10.0,
                wind_direction_deg=180,
                observed_at="2026-09-06T12:00",
                timezone="Asia/Kolkata",
                raw_payload={"seeded": True},
                fetched_at=datetime.now(timezone.utc),
            )
        )


def test_chat_turn_executes_tool_call_then_returns_final_answer(clean_weather_readings):
    _seed_weather()
    provider = FakeLLMProvider(
        [
            LLMTurn(
                text=None,
                tool_calls=[
                    ToolCall(id="toolu_1", name="get_weather", input={"latitude": 19.08, "longitude": 72.88})
                ],
                stop_reason="tool_use",
            ),
            LLMTurn(text="It's 28.0C in Mumbai.", tool_calls=[], stop_reason="end_turn"),
        ]
    )

    result = chat_turn("What's the weather in Mumbai?", provider=provider)

    assert result["reply"] == "It's 28.0C in Mumbai."
    assert len(provider.calls) == 2
    # Second call's history must contain the tool result the loop executed.
    second_call_history = provider.calls[1]["history"]
    tool_messages = [m for m in second_call_history if m["role"] == "tool"]
    assert len(tool_messages) == 1
    assert "28.0" in tool_messages[0]["content"]


def test_chat_turn_returns_direct_answer_without_tool_calls():
    provider = FakeLLMProvider([LLMTurn(text="Hello!", tool_calls=[], stop_reason="end_turn")])

    result = chat_turn("Hi", provider=provider)

    assert result["reply"] == "Hello!"
    assert len(provider.calls) == 1


def test_chat_turn_stops_after_max_iterations_without_crashing():
    looping_turn = LLMTurn(
        text=None,
        tool_calls=[ToolCall(id="toolu_x", name="list_alerts", input={})],
        stop_reason="tool_use",
    )
    provider = FakeLLMProvider([looping_turn] * 5)

    result = chat_turn("loop forever", provider=provider)

    assert len(provider.calls) == 5
    assert "reply" in result
    assert result["reply"]
