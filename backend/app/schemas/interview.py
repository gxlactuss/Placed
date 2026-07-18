from datetime import datetime
from typing import Optional

from pydantic import BaseModel

from app.models.interview import InterviewStatus


class InterviewStart(BaseModel):
    target_role: str


class InterviewTurn(BaseModel):
    speaker: str  # "ai" | "user"
    text: str
    at: datetime


class InterviewSessionRead(BaseModel):
    id: int
    target_role: str
    status: InterviewStatus
    transcript: list[InterviewTurn]
    overall_feedback: Optional[str] = None
    started_at: datetime
    ended_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class InterviewAnswerSubmit(BaseModel):
    """Sent by the client after Speech-to-Text has transcribed the user's spoken answer."""

    session_id: int
    transcribed_answer: str


class InterviewAiResponse(BaseModel):
    """Returned to the client so AVSpeechSynthesizer can speak it back."""

    session_id: int
    ai_message: str
    is_follow_up: bool
    interview_complete: bool = False
