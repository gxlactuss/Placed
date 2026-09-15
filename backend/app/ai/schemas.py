from datetime import datetime
from typing import Annotated, Optional

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


class InterviewFeedbackResponse(BaseModel):
    rating: int
    summary: str
    improvements: list[str] = []
    mistakes: list[str] = []


class InterviewAiResponse(BaseModel):
    session_id: int
    ai_message: str
    is_follow_up: bool
    interview_complete: bool = False
    ended_early: bool = False
    question_number: Optional[int] = None
    difficulty: Optional[int] = None
    calibrating: bool = False

InterviewSessionRead.model_rebuild()
