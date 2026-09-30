import logging
import secrets
from urllib.parse import urlencode

from fastapi import APIRouter, Depends, Request
from fastapi.responses import RedirectResponse
from sqlmodel import Session

from app.auth.jwt import create_access_token, hash_password
from app.core.config import settings
from app.core.rate_limit import limiter
from app.auth import oauth_service
from app.auth.routes import get_user_by_email
from app.auth.schemas import normalize_email
from database.db import get_session
from database.models.user import User

router = APIRouter(prefix="/api/auth/oauth", tags=["oauth"])
logger = logging.getLogger(__name__)


def _redirect_to_app(**params: str) -> RedirectResponse:
    url = f"{settings.app_redirect_scheme}://oauth?{urlencode(params)}"
    return RedirectResponse(url, status_code=302)


def _fail(provider: str, error: str) -> RedirectResponse:
    # provider and error can come from the query string, so cap their length.
    # Only the code before ":" is logged; OAuthError details can be long.
    logger.warning(
        "oauth_failed provider=%s error=%s", provider[:32], error.split(":", 1)[0][:64]
    )
    return _redirect_to_app(error=error)


@router.get("/{provider}/login")
@limiter.limit(lambda: settings.rate_limit_oauth, error_message="Too many sign-in attempts.")
def oauth_login(request: Request, provider: str):
    if not oauth_service.is_known(provider):
        return _fail(provider, "unknown_provider")
    if not oauth_service.is_configured(provider):
        return _fail(provider, "provider_not_configured")
    state = oauth_service.make_state(provider)
    return RedirectResponse(oauth_service.authorize_url(provider, state), status_code=302)


@router.get("/{provider}/callback")
@limiter.limit(lambda: settings.rate_limit_oauth, error_message="Too many sign-in attempts.")
def oauth_callback(
    request: Request,
    provider: str,
    code: str | None = None,
    state: str | None = None,
    error: str | None = None,
    session: Session = Depends(get_session),
):
    if error:
        return _fail(provider, error)
    if not oauth_service.is_configured(provider):
        return _fail(provider, "provider_not_configured")
    if not code or not state or not oauth_service.verify_state(provider, state):
        return _fail(provider, "invalid_state")

    try:
        email, name = oauth_service.complete_login(provider, code)
    except oauth_service.OAuthError as exc:
        return _fail(provider, str(exc))

    email = normalize_email(email)
    user = get_user_by_email(session, email)
    new_user = user is None
    if not user:
        user = User(
            email=email,
            hashed_password=hash_password(secrets.token_urlsafe(32)),
            full_name=name,
            is_verified=True,
            onboarded=False,
        )
        session.add(user)
        session.commit()
        session.refresh(user)
    elif not user.is_verified:
        # Pre-hijacking guard: anyone can sign up with an address they don't
        # own and leave it unverified. The provider has just proven that this
        # caller owns the address, so they take the account over: mark it
        # verified and replace the password nobody proved ownership for.
        user.is_verified = True
        user.verification_code = None
        user.verification_code_expires_at = None
        user.hashed_password = hash_password(secrets.token_urlsafe(32))
        session.add(user)
        session.commit()
        session.refresh(user)
        logger.info("oauth_claimed_unverified_account user_id=%s", user.id)

    logger.info(
        "oauth_success provider=%s user_id=%s new_user=%s", provider, user.id, new_user
    )
    token = create_access_token(subject=str(user.id))
    return _redirect_to_app(token=token)
