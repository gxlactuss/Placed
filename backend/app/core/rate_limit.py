"""Rate limiting for the auth endpoints (slowapi).

Buckets live in ``settings.rate_limit_storage_uri`` ("memory://" by default).
In-memory buckets reset when the process restarts and are not shared between
machines, which is fine while the API runs on a single Fly machine. Point the
URI at Redis (e.g. "redis://host:6379") before scaling out.
"""

import math
import time
from urllib.parse import urlencode

from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse, RedirectResponse
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded

from app.auth.jwt import decode_access_token
from app.core.config import settings


def client_ip(request: Request) -> str:
    """The caller's IP address.

    Fly's edge sets ``Fly-Client-IP`` to the real client address. X-Forwarded-For
    is deliberately ignored because clients can put anything in it.
    """
    fly_ip = request.headers.get("fly-client-ip", "").strip()
    if fly_ip:
        return fly_ip
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


def ip_key(request: Request) -> str:
    return f"ip:{client_ip(request)}"


def user_key(request: Request) -> str:
    """Key by the authenticated user id so OTP guessing is limited per account.

    Falls back to the IP address when there is no valid bearer token.
    """
    scheme, _, token = request.headers.get("authorization", "").partition(" ")
    if scheme.lower() == "bearer" and token:
        try:
            return f"user:{decode_access_token(token.strip())}"
        except HTTPException:
            pass
    return ip_key(request)


limiter = Limiter(
    key_func=ip_key,
    storage_uri=settings.rate_limit_storage_uri,
    strategy="moving-window",
    enabled=settings.rate_limit_enabled,
    # Bucket by endpoint function, not URL, so /oauth/{provider}/... can't be
    # used to open a fresh bucket per made-up provider name.
    key_style="endpoint",
)


def _format_wait(seconds: int) -> str:
    if seconds < 60:
        return f"{seconds} second{'s' if seconds != 1 else ''}"
    minutes = math.ceil(seconds / 60)
    return f"{minutes} minute{'s' if minutes != 1 else ''}"


def _retry_after_seconds(request: Request) -> int:
    current = getattr(request.state, "view_rate_limit", None)
    if current:
        try:
            reset_at, _ = limiter.limiter.get_window_stats(current[0], *current[1])
            return max(1, math.ceil(reset_at - time.time()))
        except Exception:
            pass
    return 60


def rate_limit_exceeded_handler(
    request: Request, exc: RateLimitExceeded
) -> JSONResponse | RedirectResponse:
    retry_after = _retry_after_seconds(request)
    # OAuth runs inside ASWebAuthenticationSession, which would show raw JSON.
    # Send it back to the app like every other OAuth error.
    if request.url.path.startswith("/api/auth/oauth/"):
        url = f"{settings.app_redirect_scheme}://oauth?{urlencode({'error': 'rate_limited'})}"
        return RedirectResponse(url, status_code=302, headers={"Retry-After": str(retry_after)})
    message = (exc.limit.error_message if exc.limit else None) or "Too many requests."
    detail = f"{message} Please try again in {_format_wait(retry_after)}."
    return JSONResponse(
        status_code=429,
        content={"detail": detail},
        headers={"Retry-After": str(retry_after)},
    )


def reset_rate_limits() -> None:
    """Clear every bucket (used by tests)."""
    limiter.reset()
