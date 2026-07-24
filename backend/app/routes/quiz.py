from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.core.auth import get_current_user_id
from app.schemas.quiz import (
    QuizAttemptSubmit,
    QuizProgressItem,
    QuizQuestion,
    QuizResultRead,
)
from database.db import get_session
from database.models.quiz import QuizDifficulty, QuizResult, QuizTopic

router = APIRouter(prefix="/api/quiz", tags=["quiz"])


@router.get("/questions", response_model=list[QuizQuestion])
def get_quiz_questions(topic: QuizTopic, difficulty: QuizDifficulty):
    # Quizzes are bundled in the client today; this server-side bank is unused.
    raise NotImplementedError("Wire up the question bank data source here")


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
