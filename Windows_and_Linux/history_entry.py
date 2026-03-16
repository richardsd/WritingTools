"""
History Entry Data Model
------------------------

Data model for a single command execution history entry.
"""

import uuid
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional


@dataclass
class HistoryEntry:
    """A recorded command execution."""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())
    command_name: str = ""
    input_text: str = ""
    output_text: str = ""
    model_name: str = ""
    source_app_name: str = ""
    matched_profile_name: str = ""

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "timestamp": self.timestamp,
            "command_name": self.command_name,
            "input_text": self.input_text,
            "output_text": self.output_text,
            "model_name": self.model_name,
            "source_app_name": self.source_app_name,
            "matched_profile_name": self.matched_profile_name,
        }

    @staticmethod
    def from_dict(d: dict) -> "HistoryEntry":
        return HistoryEntry(
            id=d.get("id", str(uuid.uuid4())),
            timestamp=d.get("timestamp", datetime.now().isoformat()),
            command_name=d.get("command_name", ""),
            input_text=d.get("input_text", ""),
            output_text=d.get("output_text", ""),
            model_name=d.get("model_name", ""),
            source_app_name=d.get("source_app_name", ""),
            matched_profile_name=d.get("matched_profile_name", ""),
        )

    @property
    def display_timestamp(self) -> str:
        try:
            dt = datetime.fromisoformat(self.timestamp)
            return dt.strftime("%Y-%m-%d %H:%M")
        except ValueError:
            return self.timestamp
