import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select

from app.auth.jwt import (
    create_access_token,
    get_current_user_id,
    hash_password,
    verify_password,
)
from app.core.config import settings
from app.auth.schemas import (
    TokenResponse,
    UserCreate,
    UserLogin,
    UserRead,
    UserUpdate,
    VerifyRequest,
)
from app.auth.email_service import send_verification_email
from database.db import get_session
from database.models.user import User

router = APIRouter(prefix="/api/auth", tags=["auth"])


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


@router.post("/signup", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def signup(payload: UserCreate, session: Session = Depends(get_session)):
    existing = session.exec(select(User).where(User.email == payload.email)).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        full_name=payload.full_name,
        target_role=payload.target_role,
    )
    session.add(user)
    session.commit()
    session.refresh(user)

    _issue_verification_code(user, session)
    session.refresh(user)

    token = create_access_token(subject=str(user.id))
    return TokenResponse(access_token=token, user=UserRead.model_validate(user))


@router.post("/verify", response_model=UserRead)
def verify_email(
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
        raise HTTPException(status_code=400, detail="That code isn't right. Try again.")

    now_naive = datetime.now(timezone.utc).replace(tzinfo=None)
    if user.verification_code_expires_at and now_naive > user.verification_code_expires_at:
        raise HTTPException(status_code=400, detail="That code expired — request a new one.")

    user.is_verified = True
    user.verification_code = None
    user.verification_code_expires_at = None
    session.add(user)
    session.commit()
    session.refresh(user)
    return UserRead.model_validate(user)


@router.post("/resend-verification", status_code=status.HTTP_204_NO_CONTENT)
def resend_verification(
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    user = session.get(User, int(user_id))
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if not user.is_verified:
        _issue_verification_code(user, session)


@router.post("/login", response_model=TokenResponse)
def login(payload: UserLogin, session: Session = Depends(get_session)):
    user = session.exec(select(User).where(User.email == payload.email)).first()
    if not user or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Incorrect email or password")

    token = create_access_token(subject=str(user.id))
    return TokenResponse(access_token=token, user=UserRead.model_validate(user))
