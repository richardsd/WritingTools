"""
App Profile Data Models
-----------------------

Data models for app-aware prompt profiles: FormattingPreset, AppMatcher, AppProfile.
"""

import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional

from active_app import ActiveAppContext


class FormattingPreset(Enum):
    """Predefined formatting instruction sets."""
    PLAIN_TEXT = "plain_text"
    MARKDOWN = "markdown"
    EMAIL_FRIENDLY = "email_friendly"
    CODE_FRIENDLY = "code_friendly"

    @property
    def instruction_text(self) -> str:
        return _PRESET_INSTRUCTIONS[self]

    @property
    def display_name(self) -> str:
        return _PRESET_DISPLAY_NAMES[self]


_PRESET_INSTRUCTIONS = {
    FormattingPreset.PLAIN_TEXT: (
        "Format your response as plain text only. "
        "Do not use any Markdown syntax such as headers (#), bold (**), italic (*), "
        "bullet points (-), numbered lists, code blocks, or links."
    ),
    FormattingPreset.MARKDOWN: (
        "Format your response using Markdown where appropriate, "
        "including headers, bullet points, bold/italic text, and code blocks."
    ),
    FormattingPreset.EMAIL_FRIENDLY: (
        "Format your response as professional email text. "
        "Use short paragraphs. Avoid Markdown syntax. "
        "Maintain a polite and professional tone."
    ),
    FormattingPreset.CODE_FRIENDLY: (
        "When including code, always wrap it in appropriate code blocks. "
        "Use inline code for short references. Prefer concise technical language."
    ),
}

_PRESET_DISPLAY_NAMES = {
    FormattingPreset.PLAIN_TEXT: "Plain Text",
    FormattingPreset.MARKDOWN: "Markdown",
    FormattingPreset.EMAIL_FRIENDLY: "Email-Friendly",
    FormattingPreset.CODE_FRIENDLY: "Code-Friendly",
}


@dataclass
class AppMatcher:
    """A single rule for matching an application."""
    match_type: str  # "app_name_contains" or "process_name_equals"
    value: str = ""

    def matches(self, ctx: ActiveAppContext) -> bool:
        if not self.value:
            return False
        lower_val = self.value.lower()
        if self.match_type == "app_name_contains":
            return lower_val in ctx.app_name.lower() or lower_val in ctx.window_title.lower()
        elif self.match_type == "process_name_equals":
            return lower_val == ctx.process_name.lower()
        return False

    def to_dict(self) -> dict:
        return {"match_type": self.match_type, "value": self.value}

    @staticmethod
    def from_dict(d: dict) -> "AppMatcher":
        return AppMatcher(match_type=d.get("match_type", "app_name_contains"), value=d.get("value", ""))


@dataclass
class AppProfile:
    """An app-aware prompt profile."""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    name: str = ""
    is_enabled: bool = True
    matchers: List[AppMatcher] = field(default_factory=list)
    formatting_preset: FormattingPreset = FormattingPreset.PLAIN_TEXT
    additional_instructions: str = ""

    def matches(self, ctx: ActiveAppContext) -> bool:
        """Return True if any matcher matches the given context."""
        return self.is_enabled and any(m.matches(ctx) for m in self.matchers)

    @property
    def combined_instructions(self) -> str:
        """Combine preset instructions with additional instructions."""
        parts = [self.formatting_preset.instruction_text]
        if self.additional_instructions.strip():
            parts.append(self.additional_instructions.strip())
        return "\n\n".join(parts)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "name": self.name,
            "is_enabled": self.is_enabled,
            "matchers": [m.to_dict() for m in self.matchers],
            "formatting_preset": self.formatting_preset.value,
            "additional_instructions": self.additional_instructions,
        }

    @staticmethod
    def from_dict(d: dict) -> "AppProfile":
        return AppProfile(
            id=d.get("id", str(uuid.uuid4())),
            name=d.get("name", ""),
            is_enabled=d.get("is_enabled", True),
            matchers=[AppMatcher.from_dict(m) for m in d.get("matchers", [])],
            formatting_preset=FormattingPreset(d.get("formatting_preset", "plain_text")),
            additional_instructions=d.get("additional_instructions", ""),
        )
