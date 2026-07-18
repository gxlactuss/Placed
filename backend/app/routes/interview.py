import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session

from app.core.auth import get_current_user_id
from app.database import get_session
from app.models.interview import InterviewSession, InterviewStatus
from app.schemas.interview import (
    InterviewAiResponse,
    InterviewAnswerSubmit,
    InterviewSessionRead,
    InterviewStart,
)
from app.services.gemini_service import generate_first_question, generate_follow_up

router = APIRouter(prefix="/api/interview", tags=["interview"])


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
        session_id=interview.id, ai_message=opening_question, is_follow_up=False
    )


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
        session_id=interview.id,
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
        id=interview.id,
        target_role=interview.target_role,
        status=interview.status,
        transcript=json.loads(interview.transcript_json),
        overall_feedback=interview.overall_feedback,
        started_at=interview.started_at,
        ended_at=interview.ended_at,
    )
