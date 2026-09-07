from datetime import datetime, timezone

from sqlalchemy import insert

from app.chat.service import chat_turn
from app.db import get_engine
from app.models import WeatherReading
from app.providers.anthropic import _translate_history
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


def test_chat_turn_max_iterations_leaves_history_well_formed_for_a_followup():
    # Regression test: the max-iterations fallback must append an assistant
    # entry so a client resubmitting the returned history in a follow-up
    # /chat call doesn't produce two consecutive same-role wire messages
    # (which Anthropic's API rejects with a 400, since roles must alternate).
    looping_turn = LLMTurn(
        text=None,
        tool_calls=[ToolCall(id="toolu_x", name="list_alerts", input={})],
        stop_reason="tool_use",
    )
    provider = FakeLLMProvider([looping_turn] * 5)

    result = chat_turn("loop forever", provider=provider)
    history = result["history"]

    assert history[-1]["role"] == "assistant"

    # Feed the returned history into a fresh translation (as a follow-up /chat
    # call would) and confirm no two consecutive wire messages share a role —
    # proving this actually prevents the invalid-role-sequence bug, not just
    # that an assistant entry exists.
    followup_history = list(history) + [{"role": "user", "content": "and now?"}]
    wire_messages = _translate_history(followup_history)
    for prev, curr in zip(wire_messages, wire_messages[1:]):
        assert prev["role"] != curr["role"], (
            f"consecutive wire messages share role {prev['role']!r}: {wire_messages}"
        )

    # And a second chat_turn call using this history as the prior history
    # must be able to proceed without error.
    second_provider = FakeLLMProvider(
        [LLMTurn(text="All clear now.", tool_calls=[], stop_reason="end_turn")]
    )
    second_result = chat_turn("and now?", history=history, provider=second_provider)
    assert second_result["reply"] == "All clear now."


def test_chat_turn_returns_deadline_fallback_when_elapsed_time_exceeds_budget(monkeypatch):
    # Simulate a deadline that has already elapsed before the loop even starts
    # its first iteration, without needing to wait in real time. Against the
    # old code (no deadline concept at all), this would just call generate()
    # normally and return its answer instead of the "taking longer than
    # expected" fallback.
    monkeypatch.setattr("app.chat.service._CHAT_TURN_DEADLINE_SECONDS", 0.0)
    provider = FakeLLMProvider([LLMTurn(text="Hello!", tool_calls=[], stop_reason="end_turn")])

    result = chat_turn("Hi", provider=provider)

    assert result["reply"] == "That's taking longer than expected — please try again in a moment."
    assert provider.calls == []
    assert result["history"][-1]["role"] == "assistant"
    assert result["history"][-1]["content"] == result["reply"]


def test_chat_turn_fast_completion_is_unaffected_by_deadline():
    # A normal, fast-completing turn must never trip the deadline check
    # (the default _CHAT_TURN_DEADLINE_SECONDS is left untouched here).
    provider = FakeLLMProvider([LLMTurn(text="Hello!", tool_calls=[], stop_reason="end_turn")])

    result = chat_turn("Hi", provider=provider)

    assert result["reply"] == "Hello!"
    assert len(provider.calls) == 1
