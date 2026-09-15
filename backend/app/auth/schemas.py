from datetime import datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field


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
    onboarded: Optional[bool] = None


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserRead
