import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlmodel import Session

from app.auth.jwt import get_current_user_id
from app.core.config import settings
from database.db import get_session
from database.models.interview import InterviewSession, InterviewStatus
from app.ai.schemas import (
    InterviewAiResponse,
    InterviewAnswerSubmit,
    InterviewFeedbackResponse,
    InterviewSessionRead,
    InterviewStart,
    ResumeSummaryRequest,
    ResumeSummaryResponse,
    TranscriptionResponse,
)
from app.ai.interview_prompts import InterviewMode, decode_context
from app.ai.llm_service import (
    generate_feedback,
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
    mode = InterviewMode.parse(payload.mode)
    context = payload.context.model_dump(exclude_none=True) if payload.context else {}

    opening_question = generate_first_question(payload.target_role, mode, context)
    transcript = [
        {"speaker": "ai", "text": opening_question, "at": datetime.now(timezone.utc).isoformat()}
    ]

    interview = InterviewSession(
        user_id=int(user_id),
        target_role=payload.target_role,
        mode=mode.value,
        # Persisted so follow-ups are prompted with the same resume material the
        # opening question came from, rather than the client resending it.
        context_json=json.dumps(context) if context else None,
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
    """Turns a recorded answer into text — the only path a spoken answer takes.

    Apple's `SFSpeechRecognizer` was dropped rather than kept as a fast path: it
    won't initialise in the Simulator, which made voice untestable without
    physical hardware. So every answer is uploaded and transcribed here.
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
    # An interviewer who has walked out doesn't come back because the client
    # posted again. Without this, an ended round is one retry away from resuming.
    if interview.status != InterviewStatus.IN_PROGRESS:
        raise HTTPException(status_code=409, detail="This interview has already ended.")

    transcript: list[dict] = json.loads(interview.transcript_json)
    transcript.append(
        {"speaker": "user", "text": payload.transcribed_answer, "at": datetime.now(timezone.utc).isoformat()}
    )

    follow_up = generate_follow_up(
        interview.target_role,
        InterviewMode.parse(interview.mode),
        decode_context(interview.context_json),
        transcript,
        payload.transcribed_answer,
    )
    transcript.append(
        {
            "speaker": "ai",
            "text": follow_up.message,
            "at": datetime.now(timezone.utc).isoformat(),
        }
    )

    interview.transcript_json = json.dumps(transcript)
    if follow_up.complete:
        # Closed on the server too, not just in the UI, so the round can't be
        # resumed by replaying `/respond` with the same session id.
        interview.status = (
            InterviewStatus.ABANDONED if follow_up.ended_early else InterviewStatus.COMPLETED
        )
        interview.ended_at = datetime.now(timezone.utc)

    session.add(interview)
    session.commit()

    return InterviewAiResponse(
        session_id=_require_id(interview),
        ai_message=follow_up.message,
        is_follow_up=True,
        # The client stops on either, but only one of them earns a "nice work".
        interview_complete=follow_up.complete,
        ended_early=follow_up.ended_early,
    )


@router.post("/{session_id}/feedback", response_model=InterviewFeedbackResponse)
def interview_feedback(
    session_id: int,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    """Marks a finished round out of 10 and says what to work on.

    Cached on the session after the first call: the debrief is stable once the
    transcript stops changing, and regenerating it every time the student scrolls
    back would spend a request from an allowance measured in tens per day.
    """
    interview = session.get(InterviewSession, session_id)
    if not interview or interview.user_id != int(user_id):
        raise HTTPException(status_code=404, detail="Interview session not found")

    if interview.overall_feedback:
        return InterviewFeedbackResponse(**json.loads(interview.overall_feedback))

    transcript: list[dict] = json.loads(interview.transcript_json)
    # Nothing said means nothing to assess, and the model would invent a score.
    if not any(turn.get("speaker") == "user" for turn in transcript):
        raise HTTPException(
            status_code=409, detail="This interview has no answers to review yet."
        )

    feedback = generate_feedback(
        interview.target_role, InterviewMode.parse(interview.mode), transcript
    )
    response = InterviewFeedbackResponse(
        rating=feedback.rating,
        summary=feedback.summary,
        improvements=feedback.improvements,
        mistakes=feedback.mistakes,
    )

    interview.overall_feedback = response.model_dump_json()
    # A round the student finished is over even if the client never said so.
    if interview.status == InterviewStatus.IN_PROGRESS:
        interview.status = InterviewStatus.COMPLETED
        interview.ended_at = datetime.now(timezone.utc)
    session.add(interview)
    session.commit()

    return response


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
