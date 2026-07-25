from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


class User(SQLModel, table=True):
    __tablename__ = "users"

    id: Optional[int] = Field(default=None, primary_key=True)
    email: str = Field(index=True, unique=True, nullable=False)
    hashed_password: str
    full_name: Optional[str] = None
    target_role: Optional[str] = None  # e.g. "Backend Engineer", used to tailor interview questions
    # Email verification (OTP). `is_verified` gates the app after sign-up.
    is_verified: bool = Field(default=False)
    verification_code: Optional[str] = None
    verification_code_expires_at: Optional[datetime] = None
    # False until the first-run onboarding flow is completed.
    onboarded: bool = Field(default=False)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
