from datetime import datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)
    full_name: Optional[str] = None
    target_role: Optional[str] = None


class UserLogin(BaseModel):
    # Accepts a username *or* an email so plain identifiers like the seeded
    # "admin" test account can sign in. Signup (UserCreate) still requires a
    # real email address.
    email: str
    password: str


class UserRead(BaseModel):
    id: int
    # str, not EmailStr, so username accounts (e.g. the seeded "admin") serialize.
    email: str
    full_name: Optional[str] = None
    target_role: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserRead
