from fastapi import APIRouter, Depends, Query
from sqlmodel import Session, func, select

from app.auth.jwt import get_current_user_id
from app.content.quiz_schemas import (
    QuizAttemptSubmit,
    QuizProgressItem,
    QuizResultRead,
    QuizSummaryRequest,
    QuizSummaryResponse,
)
from app.ai.llm_service import generate_quiz_summary
from database.db import get_session
from database.models.quiz import QuizResult

router = APIRouter(prefix="/api/quiz", tags=["quiz"])


@router.post("/summary", response_model=QuizSummaryResponse)
def quiz_summary(
    payload: QuizSummaryRequest,
    user_id: str = Depends(get_current_user_id),
):
    result = generate_quiz_summary(
        quiz_title=payload.quiz_title,
        subject=payload.subject,
        score_percentage=payload.score_percentage,
        correct_count=payload.correct_count,
        total_questions=payload.total_questions,
        missed=[item.model_dump() for item in payload.missed],
    )
    return QuizSummaryResponse(summary=result.summary, focus=result.focus)


@router.post("/submit", response_model=QuizResultRead)
def submit_quiz(
    payload: QuizAttemptSubmit,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    result = QuizResult(
        user_id=int(user_id),
        quiz_id=payload.quiz_id,
        total_questions=payload.total_questions,
        correct_answers=payload.correct_answers,
        score_percentage=payload.score_percentage,
    )
    session.add(result)
    session.commit()
    session.refresh(result)
    return result


@router.get("/history", response_model=list[QuizResultRead])
def get_quiz_history(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    return session.exec(
        select(QuizResult)
        .where(QuizResult.user_id == int(user_id))
        .order_by(QuizResult.completed_at.desc(), QuizResult.id.desc())
        .offset(offset)
        .limit(limit)
    ).all()


@router.get("/progress", response_model=list[QuizProgressItem])
def get_quiz_progress(
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    rows = session.exec(
        select(QuizResult.quiz_id, func.max(QuizResult.score_percentage))
        .where(QuizResult.user_id == int(user_id))
        .group_by(QuizResult.quiz_id)
    ).all()
    return [QuizProgressItem(quiz_id=q, best_score=s) for q, s in rows]
