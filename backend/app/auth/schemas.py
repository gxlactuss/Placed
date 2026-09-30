from datetime import datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field, field_validator


def normalize_email(email: str) -> str:
    """The canonical form of an address: how it's stored and compared.

    Signup, login and the OAuth callback all go through this, and lookups use
    lower(users.email) so rows stored before normalisation still match.
    """
    return email.strip().lower()


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)
    full_name: Optional[str] = None
    target_role: Optional[str] = None


class UserLogin(BaseModel):
    email: str
    password: str


class UserRead(BaseModel):
    id: int
    email: str
    full_name: Optional[str] = None
    target_role: Optional[str] = None
    target_company: Optional[str] = None
    is_verified: bool = False
    onboarded: bool = False
    created_at: datetime

    class Config:
        from_attributes = True


class VerifyRequest(BaseModel):
    code: str


class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    target_role: Optional[str] = None
    target_company: Optional[str] = None
    # Optional so it can be left out of a PATCH, but users.onboarded is NOT
    # NULL, so an explicit null is a 422 rather than an IntegrityError. The
    # other fields map to nullable columns, where null means "clear it".
    # Any new field backed by a NOT NULL column must be added here.
    onboarded: Optional[bool] = None

    @field_validator("onboarded")
    @classmethod
    def _not_null(cls, value, info):
        # Only runs for values the client sent; omitted fields keep the default.
        if value is None:
            raise ValueError(f"{info.field_name} cannot be null")
        return value


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserRead
