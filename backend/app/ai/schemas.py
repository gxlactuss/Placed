from datetime import datetime
from typing import Annotated, Literal, Optional

from pydantic import BaseModel, Field

from database.models.interview import InterviewStatus

_ProblemTitle = Annotated[str, Field(max_length=200)]


class DSAProblemPool(BaseModel):
    easy: list[_ProblemTitle] = Field(default_factory=list, max_length=15)
    medium: list[_ProblemTitle] = Field(default_factory=list, max_length=15)
    hard: list[_ProblemTitle] = Field(default_factory=list, max_length=15)


class InterviewContext(BaseModel):
    projects_text: Optional[str] = Field(default=None, max_length=8000)
    skills: Optional[str] = Field(default=None, max_length=2000)
    dsa_problems: Optional[DSAProblemPool] = None
    dsa_problem: Optional[str] = Field(default=None, max_length=300)
    topic: Optional[str] = Field(default=None, max_length=300)


class InterviewStart(BaseModel):
    target_role: str
    mode: str = "core_cs"
    context: Optional[InterviewContext] = None


class InterviewTurn(BaseModel):
    speaker: str
    text: str
    at: datetime
    level: Optional[int] = None
    topic: Optional[str] = None
    accuracy: Optional[int] = None
    ease: Optional[int] = None
    think_seconds: Optional[float] = None
    speaking_seconds: Optional[float] = None


class InterviewSummary(BaseModel):
    id: int
    target_role: str
    mode: Optional[str] = None
    status: InterviewStatus
    answer_count: int
    rating: Optional[int] = None
    started_at: datetime
    ended_at: Optional[datetime] = None


class InterviewSessionRead(BaseModel):
    id: int
    target_role: str
    mode: Optional[str] = None
    status: InterviewStatus
    transcript: list[InterviewTurn]
    feedback: Optional["InterviewFeedbackResponse"] = None
    started_at: datetime
    ended_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class InterviewAnswerSubmit(BaseModel):
    session_id: int
    transcribed_answer: str
    think_seconds: Optional[float] = Field(default=None, ge=0)
    speaking_seconds: Optional[float] = Field(default=None, ge=0)


class ResumeSummaryRequest(BaseModel):
    target_role: str = Field(min_length=1, max_length=200)
    projects_text: str = Field(min_length=1, max_length=8000)


class ResumeSummaryResponse(BaseModel):
    summary: str
    no_projects_found: bool = False


class TranscriptionResponse(BaseModel):
    text: str


_Score = Annotated[int, Field(ge=0, le=10)]


class RubricScores(BaseModel):
    correctness: _Score
    depth: _Score
    structure: _Score
    communication: _Score
    confidence: _Score


class AnswerScore(BaseModel):
    answer: int = Field(ge=1)
    scores: RubricScores
    score: float
    note: str = ""
    level: Optional[int] = None


class InterviewFeedbackResponse(BaseModel):
    rating: int
    summary: str
    improvements: list[str] = []
    mistakes: list[str] = []
    rubric: Optional[RubricScores] = None
    answers: list[AnswerScore] = []


class InterviewAiResponse(BaseModel):
    session_id: int
    ai_message: str
    is_follow_up: bool
    interview_complete: bool = False
    ended_early: bool = False
    question_number: Optional[int] = None
    difficulty: Optional[int] = None
    calibrating: bool = False

class ResumeDeviceSignals(BaseModel):
    has_email: bool
    has_phone: bool
    has_links: bool
    page_count: int = Field(ge=1, le=20)
    has_text_layer: bool


class ResumeReviewRequest(BaseModel):
    target_role: str = Field(min_length=1, max_length=200)
    resume_text: str = Field(min_length=50, max_length=12000)
    device: ResumeDeviceSignals


class ResumeFactor(BaseModel):
    key: str
    weight: int
    score: _Score
    reason: str = ""


class ResumeCheck(BaseModel):
    key: str
    label: str
    passed: bool
    detail: str


class ResumeImprovement(BaseModel):
    factor: Optional[str] = None
    priority: Literal["high", "medium", "low"]
    section: str = ""
    issue: str
    fix: str


class ResumeRewrite(BaseModel):
    original: str
    improved: str
    why: str = ""


class ResumeReviewResponse(BaseModel):
    overall: int = Field(ge=0, le=100)
    factors: list[ResumeFactor]
    checks: list[ResumeCheck]
    strengths: list[str] = []
    improvements: list[ResumeImprovement] = []
    rewrites: list[ResumeRewrite] = []


InterviewSessionRead.model_rebuild()
