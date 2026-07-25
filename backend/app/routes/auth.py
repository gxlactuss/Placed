from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select

from app.core.auth import (
    create_access_token,
    get_current_user_id,
    hash_password,
    verify_password,
)
from database.db import get_session
from database.models.user import User
from app.schemas.user import TokenResponse, UserCreate, UserLogin, UserRead, UserUpdate

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.get("/me", response_model=UserRead)
def me(
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    """Returns the signed-in user. The client calls this on launch to validate a
    stored token — a 401/404 here means the saved session is stale."""
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
    """Partial profile update — used by the onboarding flow to save name/role
    and mark the user onboarded. Only the fields present in the body are applied."""
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

    token = create_access_token(subject=str(user.id))
    return TokenResponse(access_token=token, user=UserRead.model_validate(user))


@router.post("/login", response_model=TokenResponse)
def login(payload: UserLogin, session: Session = Depends(get_session)):
    user = session.exec(select(User).where(User.email == payload.email)).first()
    if not user or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Incorrect email or password")

    token = create_access_token(subject=str(user.id))
    return TokenResponse(access_token=token, user=UserRead.model_validate(user))
