from datetime import datetime, timezone
from typing import Optional

from sqlmodel import Field, SQLModel


class QuizResult(SQLModel, table=True):
    __tablename__ = "quiz_results"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    quiz_id: str = Field(index=True)
    total_questions: int
    correct_answers: int
    score_percentage: int
    completed_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
