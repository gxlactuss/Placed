from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

import httpx
import jwt

from app.core.config import settings

_STATE_TTL_MINUTES = 10


class OAuthError(Exception):
    pass

_PROVIDERS = {
    "google": {
        "authorize_url": "https://accounts.google.com/o/oauth2/v2/auth",
        "token_url": "https://oauth2.googleapis.com/token",
        "userinfo_url": "https://openidconnect.googleapis.com/v1/userinfo",
        "scope": "openid email profile",
    },
    "github": {
        "authorize_url": "https://github.com/login/oauth/authorize",
        "token_url": "https://github.com/login/oauth/access_token",
        "userinfo_url": "https://api.github.com/user",
        "emails_url": "https://api.github.com/user/emails",
        "scope": "read:user user:email",
    },
}


def _credentials(provider: str) -> tuple[str, str]:
    if provider == "google":
        return settings.google_client_id, settings.google_client_secret
    if provider == "github":
        return settings.github_client_id, settings.github_client_secret
    raise OAuthError("unknown_provider")


def is_known(provider: str) -> bool:
    return provider in _PROVIDERS


def is_configured(provider: str) -> bool:
    if not is_known(provider):
        return False
    client_id, client_secret = _credentials(provider)
    return bool(client_id and client_secret)


def redirect_uri(provider: str) -> str:
    return f"{settings.oauth_redirect_base}/api/auth/oauth/{provider}/callback"

def make_state(provider: str) -> str:
    payload = {
        "provider": provider,
        "exp": datetime.now(timezone.utc) + timedelta(minutes=_STATE_TTL_MINUTES),
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def verify_state(provider: str, state: str) -> bool:
    try:
        payload = jwt.decode(state, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
    except jwt.PyJWTError:
        return False
    return payload.get("provider") == provider

def authorize_url(provider: str, state: str) -> str:
    client_id, _ = _credentials(provider)
    params = {
        "client_id": client_id,
        "redirect_uri": redirect_uri(provider),
        "response_type": "code",
        "scope": _PROVIDERS[provider]["scope"],
        "state": state,
    }
    if provider == "google":
        params["access_type"] = "online"
        params["prompt"] = "select_account"
    return _PROVIDERS[provider]["authorize_url"] + "?" + urlencode(params)


def _exchange_code(provider: str, code: str) -> str:
    client_id, client_secret = _credentials(provider)
    data = {
        "client_id": client_id,
        "client_secret": client_secret,
        "code": code,
        "redirect_uri": redirect_uri(provider),
        "grant_type": "authorization_code",
    }
    try:
        resp = httpx.post(
            _PROVIDERS[provider]["token_url"],
            data=data,
            headers={"Accept": "application/json"},
            timeout=10.0,
        )
        resp.raise_for_status()
        token = resp.json().get("access_token")
    except Exception as exc:
        raise OAuthError(f"token_exchange_failed: {exc}") from exc
    if not token:
        raise OAuthError("no_access_token")
    return token


def _fetch_profile(provider: str, access_token: str) -> tuple[str, str | None]:
    headers = {"Authorization": f"Bearer {access_token}", "Accept": "application/json"}
    try:
        with httpx.Client(timeout=10.0, headers=headers) as client:
            info = client.get(_PROVIDERS[provider]["userinfo_url"]).json()
            if provider == "google":
                email = info.get("email")
                name = info.get("name")
            else:
                name = info.get("name") or info.get("login")
                email = info.get("email")
                if not email:
                    emails = client.get(_PROVIDERS["github"]["emails_url"]).json()
                    primary = next(
                        (e for e in emails if e.get("primary") and e.get("verified")), None
                    )
                    email = primary.get("email") if primary else None
    except Exception as exc:
        raise OAuthError(f"profile_fetch_failed: {exc}") from exc
    if not email:
        raise OAuthError("no_email")
    return email, name


def complete_login(provider: str, code: str) -> tuple[str, str | None]:
    access_token = _exchange_code(provider, code)
    return _fetch_profile(provider, access_token)
