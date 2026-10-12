from typing import Optional

import sqlalchemy as sa
from sqlmodel import Field, SQLModel


class Option(SQLModel, table=True):
    __tablename__ = "Option"

    id: Optional[int] = Field(default=None, primary_key=True)
    question_id: int = Field(
        foreign_key="Question.id",
        index=True,
        nullable=False,
        ondelete="CASCADE",
    )
    label: Optional[str] = Field(default=None, nullable=True)
    text: str = Field(nullable=False)
    is_correct: bool = Field(
        default=False,
        nullable=False,
        sa_column_kwargs={"server_default": sa.text("0")},
    )
