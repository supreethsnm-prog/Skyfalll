from dataclasses import dataclass, field
from typing import Protocol


@dataclass
class ToolSpec:
    name: str
    description: str
    input_schema: dict


@dataclass
class ToolCall:
    id: str
    name: str
    input: dict
    thought_signature: str | None = None


@dataclass
class LLMTurn:
    text: str | None
    tool_calls: list[ToolCall] = field(default_factory=list)
    stop_reason: str = "end_turn"


class LLMProvider(Protocol):
    def generate(
        self, system: str, history: list[dict], tools: list[ToolSpec]
    ) -> LLMTurn: ...
