"""
History Manager
---------------

Singleton service for recording, persisting, and managing command execution history.
Stores entries in command_history.json alongside config.json.
"""

import json
import logging
import os
import sys
from typing import List, Optional

from history_entry import HistoryEntry

MAX_HISTORY_ENTRIES = 100


class HistoryManager:
    """Manages command execution history with JSON file persistence."""

    _instance: Optional["HistoryManager"] = None

    def __init__(self):
        self.entries: List[HistoryEntry] = []
        self._file_path = os.path.join(os.path.dirname(sys.argv[0]), "command_history.json")
        self.load()

    @classmethod
    def shared(cls) -> "HistoryManager":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    # ── Persistence ──────────────────────────────────────────────

    def load(self):
        if os.path.exists(self._file_path):
            try:
                with open(self._file_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                self.entries = [HistoryEntry.from_dict(d) for d in data]
                logging.debug(f"Loaded {len(self.entries)} history entries")
            except Exception as e:
                logging.error(f"Failed to load history: {e}")
                self.entries = []
        else:
            self.entries = []

    def save(self):
        try:
            with open(self._file_path, "w", encoding="utf-8") as f:
                json.dump([e.to_dict() for e in self.entries], f, indent=2)
        except Exception as e:
            logging.error(f"Failed to save history: {e}")

    # ── Recording ────────────────────────────────────────────────

    def record(
        self,
        command_name: str,
        input_text: str,
        output_text: str,
        model_name: str = "",
        source_app_name: str = "",
        matched_profile_name: str = "",
    ):
        """Record a new history entry. Respects the max-entries cap."""
        entry = HistoryEntry(
            command_name=command_name,
            input_text=input_text,
            output_text=output_text,
            model_name=model_name,
            source_app_name=source_app_name,
            matched_profile_name=matched_profile_name,
        )
        self.entries.insert(0, entry)

        # Prune to cap
        if len(self.entries) > MAX_HISTORY_ENTRIES:
            self.entries = self.entries[:MAX_HISTORY_ENTRIES]

        self.save()

    # ── Actions ──────────────────────────────────────────────────

    def delete(self, entry_id: str):
        self.entries = [e for e in self.entries if e.id != entry_id]
        self.save()

    def clear_all(self):
        self.entries.clear()
        self.save()
