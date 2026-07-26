from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from database.models.interview import InterviewStatus


class InterviewContext(BaseModel):
    """Resume-derived material the round is tailored to. All optional — a round
    started without a resume simply gets an untailored prompt."""

    projects_text: Optional[str] = Field(default=None, max_length=8000)
    skills: Optional[str] = Field(default=None, max_length=2000)
    # For the DSA round: the problem title the client picked from its bundled
    # company lists (the backend has no problem bank of its own).
    dsa_problem: Optional[str] = Field(default=None, max_length=300)
    # For the group-discussion round; the model picks one if absent.
    topic: Optional[str] = Field(default=None, max_length=300)


class InterviewStart(BaseModel):
    target_role: str
    #: An `InterviewMode` value. Unknown/absent falls back to core CS rather than
    #: failing, so an older client keeps working.
    mode: str = "core_cs"
    context: Optional[InterviewContext] = None


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


class TranscriptionResponse(BaseModel):
    """Text for a spoken answer the client couldn't transcribe on-device."""

    text: str


class InterviewFeedbackResponse(BaseModel):
    """The debrief shown once a round is over."""

    #: Out of 10, against campus-placement expectations for the target role.
    rating: int
    summary: str
    improvements: list[str] = []
    #: Answers that were wrong or badly incomplete, each carrying its correction.
    #: Empty is a legitimate result, not a failure to produce one.
    mistakes: list[str] = []


class InterviewAiResponse(BaseModel):
    """Returned to the client so AVSpeechSynthesizer can speak it back."""

    session_id: int
    ai_message: str
    is_follow_up: bool
    interview_complete: bool = False
    #: The interviewer stopped the round itself rather than it running its course
    #: — currently only when the candidate wasn't answering in good faith. Kept
    #: separate from `interview_complete` so the client can close on "nice work"
    #: or not; the two coincide today only because graceful completion is still
    #: the client's round cap.
    ended_early: bool = False
