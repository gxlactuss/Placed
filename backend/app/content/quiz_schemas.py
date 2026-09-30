from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, model_validator


class MissedQuestion(BaseModel):
    prompt: str = Field(max_length=2000)
    chosen_text: Optional[str] = Field(default=None, max_length=1000)
    correct_text: str = Field(max_length=1000)
    concept: str = Field(default="", max_length=200)


class QuizSummaryRequest(BaseModel):
    quiz_title: str = Field(max_length=200)
    subject: str = Field(default="", max_length=200)
    score_percentage: int = Field(ge=0, le=100)
    correct_count: int = Field(ge=0)
    total_questions: int = Field(ge=1)
    missed: list[MissedQuestion] = Field(default_factory=list, max_length=40)


class QuizSummaryResponse(BaseModel):
    summary: str
    focus: list[str] = []


class QuizAttemptSubmit(BaseModel):
    quiz_id: str = Field(min_length=1, max_length=100)
    total_questions: int = Field(ge=1, le=500)
    correct_answers: int = Field(ge=0, le=500)
    score_percentage: int = Field(ge=0, le=100)

    @model_validator(mode="after")
    def _correct_within_total(self) -> "QuizAttemptSubmit":
        if self.correct_answers > self.total_questions:
            raise ValueError("correct_answers can't exceed total_questions")
        return self


class QuizResultRead(BaseModel):
    id: int
    quiz_id: str
    total_questions: int
    correct_answers: int
    score_percentage: int
    completed_at: datetime

    class Config:
        from_attributes = True


class QuizProgressItem(BaseModel):
    quiz_id: str
    best_score: int
