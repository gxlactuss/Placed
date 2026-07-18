from datetime import datetime

from pydantic import BaseModel, Field

from app.models.quiz import QuizDifficulty, QuizTopic


class QuizQuestionOption(BaseModel):
    id: str
    text: str


class QuizQuestion(BaseModel):
    """Question shape returned to the client. Correct answer/explanation are
    withheld until QuizSubmit is scored server-side."""

    id: str
    topic: QuizTopic
    difficulty: QuizDifficulty
    prompt: str
    options: list[QuizQuestionOption]


class QuizAnswer(BaseModel):
    question_id: str
    selected_option_id: str


class QuizSubmit(BaseModel):
    topic: QuizTopic
    difficulty: QuizDifficulty
    answers: list[QuizAnswer]


class QuizQuestionFeedback(BaseModel):
    question_id: str
    correct: bool
    correct_option_id: str
    explanation: str


class QuizResultRead(BaseModel):
    id: int
    topic: QuizTopic
    difficulty: QuizDifficulty
    total_questions: int
    correct_answers: int
    score_percentage: float
    completed_at: datetime
    feedback: list[QuizQuestionFeedback] = Field(default_factory=list)

    class Config:
        from_attributes = True
