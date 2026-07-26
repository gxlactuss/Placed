import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlmodel import Session

from app.core.auth import get_current_user_id
from app.core.config import settings
from database.db import get_session
from database.models.interview import InterviewSession, InterviewStatus
from app.schemas.interview import (
    InterviewAiResponse,
    InterviewAnswerSubmit,
    InterviewSessionRead,
    InterviewStart,
    ResumeSummaryRequest,
    ResumeSummaryResponse,
    TranscriptionResponse,
)
from app.services.llm_service import (
    generate_first_question,
    generate_follow_up,
    summarize_projects,
    transcribe_audio,
)

router = APIRouter(prefix="/api/interview", tags=["interview"])


def _require_id(interview: InterviewSession) -> int:
    """Narrows the primary key from `Optional[int]` to `int`.

    SQLModel declares `id` optional because it's unset until the row is flushed.
    Every caller below runs after a commit or a successful `session.get`, so it
    is always populated in practice — this makes that assumption explicit, and
    fails loudly rather than silently emitting `null` if it ever stops holding.
    """
    if interview.id is None:  # pragma: no cover — unreachable after a commit
        raise HTTPException(status_code=500, detail="Interview session was not persisted.")
    return interview.id


@router.post("/start", response_model=InterviewAiResponse)
def start_interview(
    payload: InterviewStart,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    opening_question = generate_first_question(payload.target_role)
    transcript = [
        {"speaker": "ai", "text": opening_question, "at": datetime.now(timezone.utc).isoformat()}
    ]

    interview = InterviewSession(
        user_id=int(user_id),
        target_role=payload.target_role,
        status=InterviewStatus.IN_PROGRESS,
        transcript_json=json.dumps(transcript),
    )
    session.add(interview)
    session.commit()
    session.refresh(interview)

    return InterviewAiResponse(
        session_id=_require_id(interview), ai_message=opening_question, is_follow_up=False
    )


@router.post("/resume-summary", response_model=ResumeSummaryResponse)
def resume_summary(
    payload: ResumeSummaryRequest,
    # Unused, but the dependency is the auth gate — it rejects an absent or
    # invalid JWT before we spend one of the five Gemini calls a minute buys.
    user_id: str = Depends(get_current_user_id),  # noqa: ARG001
):
    """Summarises the projects the client extracted from the candidate's resume.

    Stateless on purpose — nothing resume-derived is written to the database.
    The client keeps the summary locally and feeds it into the interview, so a
    student's project text never lands in our storage on top of Google's.
    """
    summary, none_found = summarize_projects(payload.target_role, payload.projects_text)
    return ResumeSummaryResponse(summary=summary, no_projects_found=none_found)


@router.post("/transcribe", response_model=TranscriptionResponse)
async def transcribe(
    audio: UploadFile = File(...),
    # Auth gate; see `resume_summary`.
    user_id: str = Depends(get_current_user_id),  # noqa: ARG001
):
    """Transcribes a spoken answer the client couldn't handle on-device.

    The app uses Apple's on-device recogniser wherever it works — free, instant,
    and the audio never leaves the phone. This exists for the cases where that
    recogniser won't initialise (notably the Simulator, which ships no on-device
    model), so voice answers still work there.
    """
    data = await audio.read()
    if not data:
        raise HTTPException(status_code=400, detail="The recording was empty.")
    if len(data) > settings.max_audio_upload_bytes:
        raise HTTPException(status_code=413, detail="That recording is too long.")

    text = transcribe_audio(data, audio.filename or "answer.m4a", audio.content_type)
    return TranscriptionResponse(text=text)


@router.post("/respond", response_model=InterviewAiResponse)
def submit_answer(
    payload: InterviewAnswerSubmit,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    interview = session.get(InterviewSession, payload.session_id)
    if not interview or interview.user_id != int(user_id):
        raise HTTPException(status_code=404, detail="Interview session not found")

    transcript: list[dict] = json.loads(interview.transcript_json)
    transcript.append(
        {"speaker": "user", "text": payload.transcribed_answer, "at": datetime.now(timezone.utc).isoformat()}
    )

    ai_message, interview_complete = generate_follow_up(
        interview.target_role, transcript, payload.transcribed_answer
    )
    transcript.append(
        {"speaker": "ai", "text": ai_message, "at": datetime.now(timezone.utc).isoformat()}
    )

    interview.transcript_json = json.dumps(transcript)
    if interview_complete:
        interview.status = InterviewStatus.COMPLETED
        interview.ended_at = datetime.now(timezone.utc)
        # TODO: generate interview.overall_feedback via Gemini once the session ends

    session.add(interview)
    session.commit()

    return InterviewAiResponse(
        session_id=_require_id(interview),
        ai_message=ai_message,
        is_follow_up=True,
        interview_complete=interview_complete,
    )


@router.get("/{session_id}", response_model=InterviewSessionRead)
def get_interview(
    session_id: int,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    interview = session.get(InterviewSession, session_id)
    if not interview or interview.user_id != int(user_id):
        raise HTTPException(status_code=404, detail="Interview session not found")

    return InterviewSessionRead(
        id=_require_id(interview),
        target_role=interview.target_role,
        status=interview.status,
        transcript=json.loads(interview.transcript_json),
        overall_feedback=interview.overall_feedback,
        started_at=interview.started_at,
        ended_at=interview.ended_at,
    )
