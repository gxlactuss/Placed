from datetime import datetime, timezone
from enum import Enum
from typing import Optional

from sqlmodel import Field, SQLModel


class InterviewStatus(str, Enum):
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    ABANDONED = "abandoned"


class InterviewSession(SQLModel, table=True):
    __tablename__ = "interview_sessions"

    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    target_role: str  # role the mock interview is tailored to, e.g. "SDE Intern"
    # Which round this is (see `InterviewMode`). NULL on sessions created before
    # modes existed — those fall back to the general interview prompt.
    mode: Optional[str] = Field(default=None, index=True)
    # The resume-derived material the round was started with, as JSON. Persisted
    # so follow-up turns are prompted with the same projects/skills the opening
    # question came from, instead of the client resending it every turn.
    context_json: Optional[str] = None
    status: InterviewStatus = Field(default=InterviewStatus.IN_PROGRESS)
    # Serialized JSON transcript: [{"speaker": "ai"|"user", "text": "...", "at": "..."}]
    # TODO: consider a separate InterviewTurn table if transcripts grow large
    transcript_json: str = Field(default="[]")
    overall_feedback: Optional[str] = None
    started_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    ended_at: Optional[datetime] = None
