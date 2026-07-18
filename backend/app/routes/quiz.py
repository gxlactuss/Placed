from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.core.auth import get_current_user_id
from app.database import get_session
from app.models.quiz import QuizDifficulty, QuizResult, QuizTopic
from app.schemas.quiz import QuizQuestion, QuizResultRead, QuizSubmit

router = APIRouter(prefix="/api/quiz", tags=["quiz"])


@router.get("/questions", response_model=list[QuizQuestion])
def get_quiz_questions(topic: QuizTopic, difficulty: QuizDifficulty):
    # TODO: replace with a real question bank (DB table or JSON fixtures per topic/difficulty)
    raise NotImplementedError("Wire up the question bank data source here")


@router.post("/submit", response_model=QuizResultRead)
def submit_quiz(
    payload: QuizSubmit,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    # TODO: look up correct answers for payload.answers, compute score + per-question
    # feedback/explanations, then persist a QuizResult row before returning it.
    raise NotImplementedError("Wire up scoring logic against the question bank")


@router.get("/history", response_model=list[QuizResultRead])
def get_quiz_history(
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    results = session.exec(
        select(QuizResult).where(QuizResult.user_id == int(user_id))
    ).all()
    return results
