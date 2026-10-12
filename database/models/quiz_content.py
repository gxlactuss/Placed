from typing import Optional
from sqlmodel import Field, SQLModel


class Question(SQLModel, table=True):
    __tablename__ = "Question"

    id: Optional[int] = Field(default=None, primary_key=True)
    quiz_id: int = Field(
        foreign_key="Quiz.id",
        index=True,
        nullable=False,
        ondelete="CASCADE",
    )
    prompt: str = Field(nullable=False)
