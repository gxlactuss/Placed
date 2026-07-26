from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from database.models.interview import InterviewStatus


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


class ResumeSummaryRequest(BaseModel):
    """One shot: the target role plus *only* the projects section of the resume,
    which the client pulls out on-device with Vision OCR.

    The whole resume is deliberately never sent. The free Gemini tier trains on
    submitted content and allows human review, and a resume is dense PII — so
    the client strips contact details before this leaves the phone. Keep it that
    way if this endpoint grows.
    """

    target_role: str = Field(min_length=1, max_length=200)
    # Generous ceiling: a projects section is normally well under 2k characters,
    # but OCR of a dense two-column CV can run long before the client trims it.
    projects_text: str = Field(min_length=1, max_length=8000)


class ResumeSummaryResponse(BaseModel):
    summary: str
    # True when the model couldn't find any projects in the extracted text —
    # usually a resume with no projects section, or OCR that produced noise.
    no_projects_found: bool = False


class InterviewAiResponse(BaseModel):
    """Returned to the client so AVSpeechSynthesizer can speak it back."""

    session_id: int
    ai_message: str
    is_follow_up: bool
    interview_complete: bool = False
