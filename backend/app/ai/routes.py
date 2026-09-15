import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlmodel import Session, select

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
    InterviewSummary,
    ResumeSummaryRequest,
    ResumeSummaryResponse,
    TranscriptionResponse,
)
from app.ai.interview_difficulty import START_LEVEL, RoundState, opening_seed, plan_next_turn
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
    if interview.id is None:
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

    seed = opening_seed(mode)
    opening_question = generate_first_question(payload.target_role, mode, context, seed)
    opening_turn = {
        "speaker": "ai",
        "text": opening_question,
        "at": datetime.now(timezone.utc).isoformat(),
        "level": START_LEVEL,
        "topic": seed.topic if seed else "Opening",
    }
    if seed:
        opening_turn["seed"] = seed.id
    transcript = [opening_turn]

    interview = InterviewSession(
        user_id=int(user_id),
        target_role=payload.target_role,
        mode=mode.value,
        context_json=json.dumps(context) if context else None,
        status=InterviewStatus.IN_PROGRESS,
        transcript_json=json.dumps(transcript),
    )
    session.add(interview)
    session.commit()
    session.refresh(interview)

    return InterviewAiResponse(
        session_id=_require_id(interview),
        ai_message=opening_question,
        is_follow_up=False,
        question_number=1,
        difficulty=START_LEVEL,
        calibrating=True,
    )


@router.post("/resume-summary", response_model=ResumeSummaryResponse)
def resume_summary(
    payload: ResumeSummaryRequest,
    user_id: str = Depends(get_current_user_id),
):
    summary, none_found = summarize_projects(payload.target_role, payload.projects_text)
    return ResumeSummaryResponse(summary=summary, no_projects_found=none_found)


@router.post("/transcribe", response_model=TranscriptionResponse)
async def transcribe(
    audio: UploadFile = File(...),
    user_id: str = Depends(get_current_user_id),
):
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
    if interview.status != InterviewStatus.IN_PROGRESS:
        raise HTTPException(status_code=409, detail="This interview has already ended.")

    transcript: list[dict] = json.loads(interview.transcript_json)
    answer_turn: dict = {
        "speaker": "user",
        "text": payload.transcribed_answer,
        "at": datetime.now(timezone.utc).isoformat(),
    }
    if payload.think_seconds is not None:
        answer_turn["think_seconds"] = round(payload.think_seconds, 1)
    if payload.speaking_seconds is not None:
        answer_turn["speaking_seconds"] = round(payload.speaking_seconds, 1)
    transcript.append(answer_turn)

    mode = InterviewMode.parse(interview.mode)
    plan = plan_next_turn(RoundState.from_transcript(mode, transcript))
    follow_up = generate_follow_up(
        interview.target_role,
        mode,
        decode_context(interview.context_json),
        transcript,
        payload.transcribed_answer,
        plan,
    )

    answer_turn["accuracy"] = follow_up.assessment.accuracy
    answer_turn["ease"] = follow_up.assessment.ease

    reply_turn: dict = {
        "speaker": "ai",
        "text": follow_up.message,
        "at": datetime.now(timezone.utc).isoformat(),
    }
    level = plan.current_level
    if not follow_up.complete:
        level = plan.level_for(follow_up.assessment.verdict)
        reply_turn["level"] = level
        reply_turn["topic"] = plan.seed.topic if plan.seed else follow_up.assessment.topic
        if plan.seed:
            reply_turn["seed"] = plan.seed.id
    transcript.append(reply_turn)

    interview.transcript_json = json.dumps(transcript)
    if follow_up.complete:
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
        interview_complete=follow_up.complete,
        ended_early=follow_up.ended_early,
        question_number=None if follow_up.complete else plan.answered + 1,
        difficulty=level,
        calibrating=plan.seed is not None and not follow_up.complete,
    )


@router.post("/{session_id}/feedback", response_model=InterviewFeedbackResponse)
def interview_feedback(
    session_id: int,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    interview = session.get(InterviewSession, session_id)
    if not interview or interview.user_id != int(user_id):
        raise HTTPException(status_code=404, detail="Interview session not found")

    if interview.overall_feedback:
        return InterviewFeedbackResponse(**json.loads(interview.overall_feedback))

    transcript: list[dict] = json.loads(interview.transcript_json)
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
    if interview.status == InterviewStatus.IN_PROGRESS:
        interview.status = InterviewStatus.COMPLETED
        interview.ended_at = datetime.now(timezone.utc)
    session.add(interview)
    session.commit()

    return response


def _decode_feedback(raw: str | None) -> InterviewFeedbackResponse | None:
    if not raw:
        return None
    try:
        return InterviewFeedbackResponse(**json.loads(raw))
    except (TypeError, ValueError):
        return None


@router.get("", response_model=list[InterviewSummary])
def list_interviews(
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    rows = session.exec(
        select(InterviewSession)
        .where(InterviewSession.user_id == int(user_id))
        .order_by(InterviewSession.started_at.desc())
    ).all()

    summaries: list[InterviewSummary] = []
    for interview in rows:
        try:
            transcript: list[dict] = json.loads(interview.transcript_json)
        except (TypeError, ValueError):
            continue
        answers = sum(1 for turn in transcript if turn.get("speaker") == "user")
        if answers == 0:
            continue

        feedback = _decode_feedback(interview.overall_feedback)
        summaries.append(
            InterviewSummary(
                id=_require_id(interview),
                target_role=interview.target_role,
                mode=interview.mode,
                status=interview.status,
                answer_count=answers,
                rating=feedback.rating if feedback else None,
                started_at=interview.started_at,
                ended_at=interview.ended_at,
            )
        )
    return summaries


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
        mode=interview.mode,
        status=interview.status,
        transcript=json.loads(interview.transcript_json),
        feedback=_decode_feedback(interview.overall_feedback),
        started_at=interview.started_at,
        ended_at=interview.ended_at,
    )
