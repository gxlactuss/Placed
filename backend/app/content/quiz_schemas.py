from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from database.models.quiz import QuizDifficulty, QuizTopic


class MissedQuestion(BaseModel):
    """One question the student got wrong, sent up from the client.

    Carries the question itself rather than just its concept tag: a summary
    written from tags alone can only restate the tags, which is the raw output
    this endpoint exists to replace.
    """

    prompt: str = Field(max_length=2000)
    #: What they picked. `None` when they ran out of time and left it blank.
    chosen_text: Optional[str] = Field(default=None, max_length=1000)
    correct_text: str = Field(max_length=1000)
    concept: str = Field(default="", max_length=200)


class QuizSummaryRequest(BaseModel):
    quiz_title: str = Field(max_length=200)
    subject: str = Field(default="", max_length=200)
    score_percentage: int = Field(ge=0, le=100)
    correct_count: int = Field(ge=0)
    total_questions: int = Field(ge=1)
    #: Capped so one attempt can't turn into an unbounded prompt.
    missed: list[MissedQuestion] = Field(default_factory=list, max_length=40)


class QuizSummaryResponse(BaseModel):
    summary: str
    #: What to revise. Legitimately empty after a clean sweep.
    focus: list[str] = []


class QuizQuestionOption(BaseModel):
    id: str
    text: str


class QuizQuestion(BaseModel):
    """Question shape for the (still-stubbed) server-side question bank."""

    id: str
    topic: QuizTopic
    difficulty: QuizDifficulty
    prompt: str
    options: list[QuizQuestionOption]


class QuizAttemptSubmit(BaseModel):
    """A finished quiz attempt. Quizzes are bundled and scored on-device, so the
    client sends the computed result keyed by the quiz's stable id."""

    quiz_id: str
    total_questions: int
    correct_answers: int
    score_percentage: int


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
    """Best score achieved for a single quiz — what the client's per-quiz
    progress store mirrors."""

    quiz_id: str
    best_score: int
