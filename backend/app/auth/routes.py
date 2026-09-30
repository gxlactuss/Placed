import logging
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import Table, delete, func
from sqlmodel import Session, SQLModel, select

from app.auth.jwt import (
    create_access_token,
    get_current_user_id,
    hash_password,
    verify_password,
)
from app.core.config import settings
from app.core.logging import email_fingerprint
from app.core.rate_limit import limiter, user_key
from app.auth.schemas import (
    TokenResponse,
    UserCreate,
    UserLogin,
    UserRead,
    UserUpdate,
    VerifyRequest,
    normalize_email,
)
from app.auth.email_service import send_verification_email
from database.db import get_session
import database.models  # noqa: F401  (registers every table for _tables_owned_by_users)
from database.models.user import User

router = APIRouter(prefix="/api/auth", tags=["auth"])
# Never log raw emails, passwords or codes here; use user ids or email_fingerprint().
logger = logging.getLogger(__name__)


def get_user_by_email(session: Session, email: str) -> User | None:
    """Case-insensitive lookup, so rows stored before emails were normalised
    (e.g. "Bob@example.com") still match. If old data holds case-variants of
    one address, the first row wins; there is no migration merging them."""
    return session.exec(
        select(User).where(func.lower(User.email) == normalize_email(email))
    ).first()


def _issue_verification_code(user: User, session: Session) -> None:
    if settings.dev_verification_code:
        user.verification_code = settings.dev_verification_code
        user.verification_code_expires_at = None
        session.add(user)
        session.commit()
        return

    code = f"{secrets.randbelow(1_000_000):06d}"
    user.verification_code = code
    user.verification_code_expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=settings.verification_code_ttl_minutes
    )
    session.add(user)
    session.commit()
    send_verification_email(user.email, code)


@router.get("/me", response_model=UserRead)
def me(
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    user = session.get(User, int(user_id))
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserRead.model_validate(user)


@router.patch("/me", response_model=UserRead)
def update_me(
    payload: UserUpdate,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    user = session.get(User, int(user_id))
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(user, field, value)

    session.add(user)
    session.commit()
    session.refresh(user)
    return UserRead.model_validate(user)


def _tables_owned_by_users() -> list[Table]:
    """Every table with a foreign key to users.id, children before parents.

    Found from the metadata rather than listed by hand so a new per-user table
    is covered by account deletion automatically.
    """
    users = User.__table__
    return [
        table
        for table in reversed(SQLModel.metadata.sorted_tables)
        if table is not users
        and any(fk.column.table is users for fk in table.foreign_keys)
    ]


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit(
    lambda: settings.rate_limit_delete_account,
    key_func=user_key,
    error_message="Too many account deletion attempts.",
)
def delete_me(
    request: Request,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    """Permanently delete the account and everything that belongs to it.

    One transaction: either every row goes or none does. Afterwards the same
    token gets 401 because get_current_user_id no longer finds the user.
    """
    uid = int(user_id)
    for table in _tables_owned_by_users():
        session.exec(delete(table).where(table.c.user_id == uid))
    session.exec(delete(User).where(User.id == uid))
    session.commit()
    logger.info("account_deleted user_id=%s", uid)


@router.post("/signup", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit(
    lambda: settings.rate_limit_signup,
    error_message="Too many sign-up attempts.",
)
def signup(request: Request, payload: UserCreate, session: Session = Depends(get_session)):
    email = normalize_email(payload.email)
    if get_user_by_email(session, email):
        logger.info(
            "signup_rejected reason=email_taken email_hash=%s", email_fingerprint(email)
        )
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        email=email,
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name,
        target_role=payload.target_role,
    )
    session.add(user)
    session.commit()
    session.refresh(user)

    _issue_verification_code(user, session)
    session.refresh(user)

    logger.info("signup_success user_id=%s", user.id)
    token = create_access_token(subject=str(user.id))
    return TokenResponse(access_token=token, user=UserRead.model_validate(user))


@router.post("/verify", response_model=UserRead)
@limiter.limit(
    lambda: settings.rate_limit_verify,
    key_func=user_key,
    error_message="Too many verification attempts.",
)
def verify_email(
    request: Request,
    payload: VerifyRequest,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    user = session.get(User, int(user_id))
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user.is_verified:
        return UserRead.model_validate(user)

    if not user.verification_code or not secrets.compare_digest(
        user.verification_code, payload.code
    ):
        logger.info("verify_failed user_id=%s reason=wrong_code", user.id)
        raise HTTPException(status_code=400, detail="That code isn't right. Try again.")

    now_naive = datetime.now(timezone.utc).replace(tzinfo=None)
    if user.verification_code_expires_at and now_naive > user.verification_code_expires_at:
        logger.info("verify_failed user_id=%s reason=expired", user.id)
        raise HTTPException(status_code=400, detail="That code expired. Request a new one.")

    user.is_verified = True
    user.verification_code = None
    user.verification_code_expires_at = None
    session.add(user)
    session.commit()
    session.refresh(user)
    logger.info("verify_success user_id=%s", user.id)
    return UserRead.model_validate(user)


@router.post("/resend-verification", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit(
    lambda: settings.rate_limit_resend_verification,
    key_func=user_key,
    error_message="A code was sent recently.",
)
def resend_verification(
    request: Request,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    user = session.get(User, int(user_id))
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if not user.is_verified:
        _issue_verification_code(user, session)
        logger.info("verification_resent user_id=%s", user.id)


@router.post("/login", response_model=TokenResponse)
@limiter.limit(
    lambda: settings.rate_limit_login,
    error_message="Too many sign-in attempts.",
)
def login(request: Request, payload: UserLogin, session: Session = Depends(get_session)):
    user = get_user_by_email(session, payload.email)
    if not user or not verify_password(payload.password, user.hashed_password):
        logger.info(
            "login_failed reason=%s email_hash=%s",
            "unknown_email" if not user else "bad_password",
            email_fingerprint(payload.email),
        )
        raise HTTPException(status_code=401, detail="Incorrect email or password")

    logger.info("login_success user_id=%s", user.id)
    token = create_access_token(subject=str(user.id))
    return TokenResponse(access_token=token, user=UserRead.model_validate(user))
