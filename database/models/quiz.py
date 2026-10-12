from datetime import datetime, timezone
from enum import Enum
from typing import Optional

import sqlalchemy as sa
from sqlalchemy import CheckConstraint, Index
from sqlmodel import Field, SQLModel


class QuizDifficulty(str, Enum):
    EASY = "Easy"
    MEDIUM = "Medium"
    HARD = "Hard"


class Quiz(SQLModel, table=True):
    __tablename__ = "Quiz"
    __table_args__ = (
        CheckConstraint("difficulty IN ('Easy', 'Medium', 'Hard')", name="ck_quiz_difficulty"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    slug: str = Field(unique=True, index=True, nullable=False)
    title: str = Field(nullable=False)
    category: Optional[str] = Field(default=None, nullable=True)
    difficulty: QuizDifficulty = Field(
        default=QuizDifficulty.MEDIUM,
        nullable=False,
        sa_column_kwargs={"server_default": sa.text("'Medium'")},
    )
    questions_to_pass: Optional[int] = Field(default=None, nullable=True)


class QuizResult(SQLModel, table=True):
    __tablename__ = "quiz_results"
    __table_args__ = (
        # GET /api/quiz/history: WHERE user_id = ? ORDER BY completed_at DESC
        Index("ix_quiz_results_user_completed", "user_id", "completed_at"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True, nullable=False)
    quiz_id: str = Field(index=True, nullable=False)
    total_questions: Optional[int] = Field(default=None, nullable=True)
    correct_answers: Optional[int] = Field(default=None, nullable=True)
    score_percentage: Optional[int] = Field(default=None, nullable=True)
    score: Optional[int] = Field(default=None, nullable=True)
    completed_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        nullable=False,
        sa_column_kwargs={"server_default": sa.text("CURRENT_TIMESTAMP")},
    )
    submitted_at: Optional[datetime] = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        nullable=True,
        sa_column_kwargs={"server_default": sa.text("CURRENT_TIMESTAMP")},
    )


# Consolidated submission alias for backwards compatibility
Submission = QuizResult
