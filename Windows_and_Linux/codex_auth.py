"""
Codex OAuth Authentication
--------------------------

Handles PKCE generation, authorization URL construction, token exchange,
token refresh, and JWT parsing for the OpenAI Codex OAuth flow.
"""

import base64
import hashlib
import json
import logging
import os
import secrets
import string
import time
from dataclasses import dataclass
from typing import Optional
from urllib.parse import urlencode

import requests

# ── Constants ────────────────────────────────────────────────────

CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
ISSUER = "https://auth.openai.com"
REDIRECT_PORT = 1455
REDIRECT_URI = f"http://localhost:{REDIRECT_PORT}/auth/callback"
SCOPES = "openid profile email offline_access"
RESPONSES_ENDPOINT = "https://chatgpt.com/backend-api/codex/responses"
CALLBACK_TIMEOUT_SECONDS = 5 * 60  # 5 minutes


# ── PKCE ─────────────────────────────────────────────────────────

@dataclass
class PkceCodes:
    verifier: str
    challenge: str


def generate_pkce() -> PkceCodes:
    """Generate PKCE code verifier (43 chars, RFC 7636) and S256 challenge."""
    chars = string.ascii_letters + string.digits + "-._~"
    verifier = "".join(secrets.choice(chars) for _ in range(43))
    digest = hashlib.sha256(verifier.encode("utf-8")).digest()
    challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return PkceCodes(verifier=verifier, challenge=challenge)


def generate_state() -> str:
    """Generate a random OAuth state parameter (32 bytes, base64url)."""
    return base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=").decode("ascii")


# ── Authorization URL ────────────────────────────────────────────

def build_authorize_url(pkce: PkceCodes, state: str) -> str:
    params = {
        "response_type": "code",
        "client_id": CLIENT_ID,
        "redirect_uri": REDIRECT_URI,
        "scope": SCOPES,
        "code_challenge": pkce.challenge,
        "code_challenge_method": "S256",
        "id_token_add_organizations": "true",
        "codex_cli_simplified_flow": "true",
        "state": state,
        "originator": "writing-tools-desktop",
    }
    return f"{ISSUER}/oauth/authorize?{urlencode(params)}"


# ── OAuth Tokens ─────────────────────────────────────────────────

@dataclass
class OAuthTokens:
    access_token: str
    refresh_token: str
    expires_at: float  # Unix timestamp
    account_id: Optional[str] = None

    @property
    def is_expired(self) -> bool:
        return time.time() >= self.expires_at

    @property
    def is_expiring_soon(self) -> bool:
        return time.time() + 300 >= self.expires_at  # within 5 minutes

    def to_dict(self) -> dict:
        return {
            "access_token": self.access_token,
            "refresh_token": self.refresh_token,
            "expires_at": self.expires_at,
            "account_id": self.account_id,
        }

    @staticmethod
    def from_dict(d: dict) -> "OAuthTokens":
        return OAuthTokens(
            access_token=d["access_token"],
            refresh_token=d["refresh_token"],
            expires_at=d.get("expires_at", 0.0),
            account_id=d.get("account_id"),
        )


# ── Token Exchange ───────────────────────────────────────────────

def exchange_code_for_tokens(code: str, pkce_verifier: str) -> OAuthTokens:
    """Exchange an authorization code for OAuth tokens."""
    resp = requests.post(
        f"{ISSUER}/oauth/token",
        data={
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": REDIRECT_URI,
            "client_id": CLIENT_ID,
            "code_verifier": pkce_verifier,
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=30,
    )

    if not resp.ok:
        logging.error(f"Token exchange failed: {resp.status_code} — {resp.text}")
        raise RuntimeError(f"Token exchange failed: HTTP {resp.status_code}")

    data = resp.json()
    expires_in = data.get("expires_in", 3600)
    account_id = _parse_account_id(data.get("id_token"))

    return OAuthTokens(
        access_token=data["access_token"],
        refresh_token=data["refresh_token"],
        expires_at=time.time() + expires_in,
        account_id=account_id,
    )


def refresh_access_token(refresh_token: str) -> OAuthTokens:
    """Refresh an expired access token."""
    resp = requests.post(
        f"{ISSUER}/oauth/token",
        data={
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": CLIENT_ID,
        },
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=30,
    )

    if not resp.ok:
        logging.error(f"Token refresh failed: {resp.status_code} — {resp.text}")
        raise RuntimeError(f"Token refresh failed: HTTP {resp.status_code}")

    data = resp.json()
    expires_in = data.get("expires_in", 3600)
    account_id = _parse_account_id(data.get("id_token"))

    return OAuthTokens(
        access_token=data["access_token"],
        refresh_token=data["refresh_token"],
        expires_at=time.time() + expires_in,
        account_id=account_id,
    )


# ── JWT Parsing ──────────────────────────────────────────────────

def _parse_account_id(id_token: Optional[str]) -> Optional[str]:
    """Extract the account ID from a JWT id_token."""
    if not id_token:
        return None
    try:
        parts = id_token.split(".")
        if len(parts) != 3:
            return None
        # Add padding for base64
        payload_b64 = parts[1]
        padding = 4 - len(payload_b64) % 4
        if padding != 4:
            payload_b64 += "=" * padding
        payload = json.loads(base64.urlsafe_b64decode(payload_b64))

        # Try multiple sources
        if "chatgpt_account_id" in payload:
            return payload["chatgpt_account_id"]
        auth_claims = payload.get("https://api.openai.com/auth", {})
        if isinstance(auth_claims, dict) and "chatgpt_account_id" in auth_claims:
            return auth_claims["chatgpt_account_id"]
        orgs = payload.get("organizations")
        if isinstance(orgs, list) and orgs:
            return orgs[0].get("id")
        return payload.get("email")
    except Exception as e:
        logging.warning(f"Failed to parse JWT: {e}")
        return None
