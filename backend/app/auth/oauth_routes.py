import secrets
from urllib.parse import urlencode

from fastapi import APIRouter, Depends
from fastapi.responses import RedirectResponse
from sqlmodel import Session, select

from app.auth.jwt import create_access_token, hash_password
from app.core.config import settings
from app.auth import oauth_service
from database.db import get_session
from database.models.user import User

router = APIRouter(prefix="/api/auth/oauth", tags=["oauth"])


def _redirect_to_app(**params: str) -> RedirectResponse:
    url = f"{settings.app_redirect_scheme}://oauth?{urlencode(params)}"
    return RedirectResponse(url, status_code=302)


@router.get("/{provider}/login")
def oauth_login(provider: str):
    if not oauth_service.is_known(provider):
        return _redirect_to_app(error="unknown_provider")
    if not oauth_service.is_configured(provider):
        return _redirect_to_app(error="provider_not_configured")
    state = oauth_service.make_state(provider)
    return RedirectResponse(oauth_service.authorize_url(provider, state), status_code=302)


@router.get("/{provider}/callback")
def oauth_callback(
    provider: str,
    code: str | None = None,
    state: str | None = None,
    error: str | None = None,
    session: Session = Depends(get_session),
):
    if error:
        return _redirect_to_app(error=error)
    if not oauth_service.is_configured(provider):
        return _redirect_to_app(error="provider_not_configured")
    if not code or not state or not oauth_service.verify_state(provider, state):
        return _redirect_to_app(error="invalid_state")

    try:
        email, name = oauth_service.complete_login(provider, code)
    except oauth_service.OAuthError as exc:
        return _redirect_to_app(error=str(exc))

    user = session.exec(select(User).where(User.email == email)).first()
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

    token = create_access_token(subject=str(user.id))
    return _redirect_to_app(token=token)
