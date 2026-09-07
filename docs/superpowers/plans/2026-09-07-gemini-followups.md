# Gemini Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out the two findings the previous sprint's final review deferred, before any new feature work starts. Neither is a "fix a bug" task in the usual sense — one turns out, on live verification, to already work correctly and needs its behavior locked in with a real test and documented; the other is a cheap hardening with no design ambiguity.

**Architecture:** No new components. Both changes live entirely in `app/providers/gemini.py` and its test file.

**Tech Stack:** Same as the rest of the backend.

**Spec:** docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md (no spec changes needed — this closes gaps in an already-spec-compliant sprint).

## Background — what was deferred and why we're revisiting now

The Gemini LLM provider sprint's final review (merged commit `ce46c55`) found two issues and explicitly recommended deferring both as follow-ups rather than merge blockers. Standard practice would leave them as backlog. This plan closes them now instead, per project convention: a sprint isn't finished while its ledger has an open deferred item.

**Finding 1 (previously "Important"), now VERIFIED SAFE IN PRACTICE, not a bug:** Gemini has no tool-call IDs — it matches a `functionResponse` to its `functionCall` by function name alone. The worry was: if one turn emits two calls to the *same* tool with different arguments (a realistic pattern — "compare weather in Mumbai and Delhi" plausibly produces two `get_weather` calls), both responses carry the identical name, and nothing but position disambiguates them.

This was tested live against the real Gemini API during this planning pass:
- Prompted `gemini-2.5-flash` with "Compare the weather in Mumbai (19.05, 72.87) and Delhi (28.6, 77.2). Call get_weather for both." — it emitted exactly 2 `functionCall` parts, both named `get_weather`, with distinct `args` (Mumbai's coordinates first, Delhi's second).
- Sent back two `functionResponse` parts in the SAME order as the calls, with deliberately distinguishable fake values (`temperature_c: 99.0` for the first, `temperature_c: 11.0` for the second, i.e. Mumbai=99, Delhi=11 — values chosen so a mix-up would be obvious).
- Gemini's final answer: *"The temperature in Mumbai is 99 degrees Celsius, and in Delhi, it is 11 degrees Celsius."* — correctly attributed, matching send order.

Conclusion: Gemini positionally disambiguates same-named calls when responses are returned in the same order as the calls, and `app/providers/gemini.py::_translate_history`'s existing implementation ALREADY preserves that order (it appends functionResponse parts to `contents` in the exact order the `tool`-role history entries appear, which is the order `chat_turn` produced them in — no reordering, no name-keyed lookup that could scramble order). **No code fix is needed.** What's needed: a test that locks this behavior in at the unit level (today it is genuinely untested — the existing batching test deliberately uses two *different*-named tools), and a code comment documenting the reliance, since Google's API docs describe matching "by name" without formally guaranteeing order-based disambiguation for same-named calls — this is verified-empirical behavior, not a documented contract, and a future model version silently changing it would be a real regression risk worth flagging in the code for whoever touches this file next.

**Finding 2 ("Minor"), a cheap hardening — implement now:** Gemini has no call IDs, so `_handle a synthesized one `f"gemini-{index}"` per response, which resets every `generate()` call and can repeat across a conversation's rounds (round 1 and round 2 can both mint `"gemini-0"`). This is harmless today because the server always attaches `"name"` to tool-role entries, so the id is never actually looked up — but it's a latent trap for anyone building on this code later (e.g. a future feature that logs or correlates by tool-call id across a whole conversation would silently collide). Fix: make the synthesized id globally unique for the life of the process, not just unique within one `generate()` call.

## Global Constraints

- No behavior change to the translation's actual wire output beyond the id uniqueness fix — Finding 1's resolution is test-and-document only, not a code change to the translation logic itself (it was already correct).
- Existing tests must not regress: 106/106 baseline.

---

### Task 1: Lock in same-name parallel tool-call ordering + globally unique synthesized IDs

**Files:**
- Modify: `backend/app/providers/gemini.py`
- Modify: `backend/tests/test_gemini_llm_provider.py`

**Interfaces:**
- No public interface changes — `GeminiLLMProvider.generate()` signature and `LLMTurn`/`ToolCall` shapes are unchanged. `ToolCall.id` values change from `f"gemini-{index}"` (unique only within one `generate()` call) to a globally-unique value (unique for the life of the process).

- [ ] **Step 1: Write the failing test for same-name parallel tool-call ordering**

Add to `backend/tests/test_gemini_llm_provider.py`:

```python
def test_same_name_parallel_tool_results_preserve_call_order():
    """Gemini has no call ids — a functionResponse is matched to its
    functionCall by name alone. When one turn calls the SAME tool twice
    (e.g. "compare weather in Mumbai and Delhi"), both responses carry an
    identical name, and disambiguation depends entirely on returning the
    responses in the same order the calls were made.

    Verified live against the real Gemini API during planning: prompting
    gemini-2.5-flash to call get_weather for two different coordinates in
    one turn produced two functionCall parts in a stable order, and
    sending back functionResponse parts in that same order was correctly
    attributed by the model (Mumbai's response was not swapped with
    Delhi's). This test locks in the CODE-LEVEL half of that behavior:
    _translate_history must never reorder tool-role history entries
    relative to the order they were appended in.
    """
    capture: dict = {}
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TEXT_PAYLOAD, capture))

    history = [
        {"role": "user", "content": "Compare weather in Mumbai and Delhi"},
        {
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {"id": "c1", "name": "get_weather", "input": {"latitude": 19.05, "longitude": 72.87}},
                {"id": "c2", "name": "get_weather", "input": {"latitude": 28.6, "longitude": 77.2}},
            ],
        },
        # Order matters: Mumbai's result must stay first, Delhi's second,
        # even though both entries share the same tool name.
        {"role": "tool", "tool_call_id": "c1", "name": "get_weather", "content": '{"temperature_c": 99.0}'},
        {"role": "tool", "tool_call_id": "c2", "name": "get_weather", "content": '{"temperature_c": 11.0}'},
    ]

    provider.generate(system="s", history=history, tools=[])

    contents = capture["body"]["contents"]
    # Both functionCall parts land in the assistant/model turn, in request order.
    model_turn = contents[1]
    assert [p["functionCall"]["args"] for p in model_turn["parts"]] == [
        {"latitude": 19.05, "longitude": 72.87},
        {"latitude": 28.6, "longitude": 77.2},
    ]
    # Both functionResponse parts batch into one message, in the SAME order
    # as the calls — this is the exact property Gemini relies on to
    # disambiguate two identically-named results.
    response_turn = contents[2]
    responses = [p["functionResponse"]["response"] for p in response_turn["parts"]]
    assert responses == [{"temperature_c": 99.0}, {"temperature_c": 11.0}]


def test_synthesized_tool_call_ids_are_unique_across_generate_calls():
    """A synthesized id that resets to gemini-0/gemini-1/... on every
    generate() call would repeat across rounds of one conversation (round
    1 and round 2 could both mint "gemini-0"). Nothing currently depends
    on cross-round uniqueness (the server always attaches an explicit
    "name" to tool-role entries, so the id->name fallback is never
    consulted in practice) — but it's a latent trap for any future code
    that correlates by tool-call id across a whole conversation, so ids
    must be unique for the life of the process, not just within one call.
    """
    provider = GeminiLLMProvider(api_key="k", client=_client_returning(_TOOL_PAYLOAD))

    turn1 = provider.generate(system="s", history=[{"role": "user", "content": "a"}], tools=[])
    turn2 = provider.generate(system="s", history=[{"role": "user", "content": "b"}], tools=[])

    ids_seen = {call.id for call in turn1.tool_calls} | {call.id for call in turn2.tool_calls}
    assert len(ids_seen) == len(turn1.tool_calls) + len(turn2.tool_calls)
```

- [ ] **Step 2: Run the tests, verify they fail**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_gemini_llm_provider.py -v`
Expected: `test_same_name_parallel_tool_results_preserve_call_order` PASSES already (the translation logic was already correct — this step confirms that with evidence, it is not a placeholder). `test_synthesized_tool_call_ids_are_unique_across_generate_calls` FAILS, because `id=f"gemini-{index}"` resets every call, so both turns mint `"gemini-0"`.

- [ ] **Step 3: Fix the id generator in `app/providers/gemini.py`**

Add `import itertools` to the top of the file, and above the `GeminiLLMProvider` class definition add:

```python
_call_id_counter = itertools.count()
```

In `generate()`, change:

```python
                tool_calls.append(
                    ToolCall(
                        # Gemini supplies no call id; synthesize one that is
                        # unique within this turn for our canonical format.
                        id=f"gemini-{index}",
                        name=function_call["name"],
                        input=function_call.get("args") or {},
                    )
                )
```

to:

```python
                tool_calls.append(
                    ToolCall(
                        # Gemini supplies no call id. Synthesized ids must be
                        # unique for the life of the process, not just within
                        # one generate() call — an index-based id would repeat
                        # across a conversation's rounds (round 1 and round 2
                        # could both mint "gemini-0"), which is harmless today
                        # (the server always attaches "name" to tool-role
                        # history entries, so this id is never looked up) but
                        # is a trap for any future code that correlates by id
                        # across a whole conversation.
                        id=f"gemini-{next(_call_id_counter)}",
                        name=function_call["name"],
                        input=function_call.get("args") or {},
                    )
                )
```

Remove the now-unused `index` from the `for index, part in enumerate(parts):` loop if nothing else in the loop body uses it — change it back to `for part in parts:` if that's the case (check the surrounding code first).

- [ ] **Step 4: Document the same-name ordering reliance in the module docstring**

In `app/providers/gemini.py`'s module docstring, after the existing bullet about function calls carrying no id, add:

```
  - when one turn calls the SAME tool more than once (Gemini has no id to
    tell such calls apart), disambiguation relies entirely on returning
    functionResponse parts in the same order the functionCall parts
    arrived in — verified against the real API (see
    docs/superpowers/plans/2026-09-07-gemini-followups.md for the live
    transcript), but not a behavior Google's API docs formally guarantee.
    _translate_history must never reorder tool-role history entries
    relative to their append order.
```

- [ ] **Step 5: Run the tests, verify they pass**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/test_gemini_llm_provider.py -v`
Expected: PASS, all tests including both new ones.

- [ ] **Step 6: Run the full suite**

Run from `backend/`: `.venv/Scripts/python.exe -m pytest tests/ -v`
Expected: 106 existing + 2 new all PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/app/providers/gemini.py backend/tests/test_gemini_llm_provider.py
git commit -m "test: lock in same-name parallel tool-call ordering; fix: make synthesized Gemini tool-call ids globally unique"
```
