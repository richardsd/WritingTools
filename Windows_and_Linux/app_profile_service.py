"""
App Profile Service
-------------------

Singleton-style service for managing app-aware prompt profiles.
Persists profiles to app_profiles.json alongside config.json.
"""

import json
import logging
import os
import sys
from typing import List, Optional

from active_app import ActiveAppContext
from app_profile import AppMatcher, AppProfile, FormattingPreset


class AppProfileService:
    """Manages app-aware prompt profiles: CRUD, persistence, and prompt enrichment."""

    _instance: Optional["AppProfileService"] = None

    def __init__(self):
        self.profiles: List[AppProfile] = []
        self._file_path = os.path.join(os.path.dirname(sys.argv[0]), "app_profiles.json")
        self.load()

    @classmethod
    def shared(cls) -> "AppProfileService":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    # ── Persistence ──────────────────────────────────────────────

    def load(self):
        if os.path.exists(self._file_path):
            try:
                with open(self._file_path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                self.profiles = [AppProfile.from_dict(d) for d in data]
                logging.debug(f"Loaded {len(self.profiles)} app profiles")
            except Exception as e:
                logging.error(f"Failed to load app profiles: {e}")
                self.profiles = []
        else:
            self.profiles = self._starter_profiles()
            self.save()

    def save(self):
        try:
            with open(self._file_path, "w", encoding="utf-8") as f:
                json.dump([p.to_dict() for p in self.profiles], f, indent=4)
            logging.debug(f"Saved {len(self.profiles)} app profiles")
        except Exception as e:
            logging.error(f"Failed to save app profiles: {e}")

    # ── CRUD ─────────────────────────────────────────────────────

    def add_profile(self, profile: AppProfile):
        self.profiles.append(profile)
        self.save()

    def update_profile(self, profile: AppProfile):
        for i, p in enumerate(self.profiles):
            if p.id == profile.id:
                self.profiles[i] = profile
                self.save()
                return
        # If not found, add it
        self.add_profile(profile)

    def delete_profile(self, profile_id: str):
        self.profiles = [p for p in self.profiles if p.id != profile_id]
        self.save()

    # ── Resolution ───────────────────────────────────────────────

    def resolve_profile(self, ctx: ActiveAppContext) -> Optional[AppProfile]:
        """Return the first enabled profile whose matchers match the context."""
        for profile in self.profiles:
            if profile.matches(ctx):
                return profile
        return None

    def enrich_system_instruction(self, instruction: str, ctx: ActiveAppContext) -> str:
        """
        Append profile-specific instructions to *instruction*.
        If no profile matches, append a plain-text fallback.
        """
        profile = self.resolve_profile(ctx)
        if profile:
            return f"{instruction}\n\n[App-Aware Formatting Instructions]\n{profile.combined_instructions}"
        # Invisible plain-text fallback
        return (
            f"{instruction}\n\n[Formatting Instructions]\n"
            "Format your response as plain text only. "
            "Do not use any Markdown syntax such as headers (#), bold (**), italic (*), "
            "bullet points (-), numbered lists, code blocks, or links."
        )

    # ── Starter profiles ─────────────────────────────────────────

    @staticmethod
    def _starter_profiles() -> List[AppProfile]:
        return [
            AppProfile(
                name="VS Code / Cursor",
                matchers=[
                    AppMatcher("app_name_contains", "Code"),
                    AppMatcher("app_name_contains", "Cursor"),
                ],
                formatting_preset=FormattingPreset.CODE_FRIENDLY,
            ),
            AppProfile(
                name="Obsidian",
                matchers=[AppMatcher("app_name_contains", "Obsidian")],
                formatting_preset=FormattingPreset.MARKDOWN,
            ),
            AppProfile(
                name="Slack",
                matchers=[AppMatcher("app_name_contains", "Slack")],
                formatting_preset=FormattingPreset.PLAIN_TEXT,
            ),
            AppProfile(
                name="Teams",
                matchers=[AppMatcher("app_name_contains", "Teams")],
                formatting_preset=FormattingPreset.PLAIN_TEXT,
            ),
            AppProfile(
                name="Email Clients",
                matchers=[
                    AppMatcher("app_name_contains", "Outlook"),
                    AppMatcher("app_name_contains", "Thunderbird"),
                    AppMatcher("app_name_contains", "Mail"),
                ],
                formatting_preset=FormattingPreset.EMAIL_FRIENDLY,
            ),
        ]
