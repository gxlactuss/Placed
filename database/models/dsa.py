from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import UniqueConstraint
from sqlmodel import Field, SQLModel


class SolvedProblem(SQLModel, table=True):
    __tablename__ = "solved_problems"
    __table_args__ = (UniqueConstraint("user_id", "slug", name="uq_solved_user_slug"),)

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    slug: str = Field(index=True)
    solved_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
