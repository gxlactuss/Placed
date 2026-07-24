from datetime import datetime

from pydantic import BaseModel

from database.models.quiz import QuizDifficulty, QuizTopic


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
