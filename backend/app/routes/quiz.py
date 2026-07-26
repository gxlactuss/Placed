from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.core.auth import get_current_user_id
from app.schemas.quiz import (
    QuizAttemptSubmit,
    QuizProgressItem,
    QuizQuestion,
    QuizResultRead,
    QuizSummaryRequest,
    QuizSummaryResponse,
)
from app.services.llm_service import generate_quiz_summary
from database.db import get_session
from database.models.quiz import QuizDifficulty, QuizResult, QuizTopic

router = APIRouter(prefix="/api/quiz", tags=["quiz"])


@router.get("/questions", response_model=list[QuizQuestion])
def get_quiz_questions(topic: QuizTopic, difficulty: QuizDifficulty):
    # Quizzes are bundled in the client today; this server-side bank is unused.
    raise NotImplementedError("Wire up the question bank data source here")


@router.post("/summary", response_model=QuizSummaryResponse)
def quiz_summary(
    payload: QuizSummaryRequest,
    # Unused, but the dependency is the auth gate — it rejects an absent or
    # invalid JWT before we spend a model request on it.
    user_id: str = Depends(get_current_user_id),  # noqa: ARG001
):
    """Explains a finished quiz instead of restating the score.

    Stateless, like the resume summary: quizzes are bundled and scored on-device,
    so the questions arrive with the request and nothing is written back. That
    also means there's nothing to cache against — the client holds the result for
    as long as the results screen is up, and a retake is a genuinely new attempt.
    """
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
    """Records a finished, on-device-scored attempt."""
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
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    return session.exec(
        select(QuizResult).where(QuizResult.user_id == int(user_id))
    ).all()


@router.get("/progress", response_model=list[QuizProgressItem])
def get_quiz_progress(
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    """Best score per quiz — the shape the client's progress store mirrors."""
    rows = session.exec(
        select(QuizResult).where(QuizResult.user_id == int(user_id))
    ).all()
    best: dict[str, int] = {}
    for row in rows:
        if row.score_percentage > best.get(row.quiz_id, -1):
            best[row.quiz_id] = row.score_percentage
    return [QuizProgressItem(quiz_id=q, best_score=s) for q, s in best.items()]
