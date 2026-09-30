from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import Index
from sqlmodel import Field, SQLModel


class QuizResult(SQLModel, table=True):
    __tablename__ = "quiz_results"
    __table_args__ = (
        # GET /api/quiz/history: WHERE user_id = ? ORDER BY completed_at DESC
        Index("ix_quiz_results_user_completed", "user_id", "completed_at"),
    )

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    quiz_id: str = Field(index=True)
    total_questions: int
    correct_answers: int
    score_percentage: int
    completed_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
