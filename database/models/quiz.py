from datetime import datetime, timezone
from enum import Enum
from typing import Optional

from sqlmodel import Field, SQLModel


class QuizTopic(str, Enum):
    CS_FUNDAMENTALS = "cs_fundamentals"
    DSA = "dsa"
    APTITUDE = "aptitude"


class QuizDifficulty(str, Enum):
    EASY = "easy"
    MEDIUM = "medium"
    HARD = "hard"


class QuizResult(SQLModel, table=True):
    """One quiz attempt. Quizzes are bundled and scored on-device, so the client
    reports the finished result keyed by the quiz's stable id (e.g. "cs-dbms-01");
    best-per-quiz is derived from these rows."""

    __tablename__ = "quiz_results"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    quiz_id: str = Field(index=True)
    total_questions: int
    correct_answers: int
    score_percentage: int  # 0-100, matches the client's best-score unit
    completed_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
