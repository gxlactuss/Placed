from fastapi import APIRouter, Depends, status
from sqlmodel import Session, select

from app.auth.jwt import get_current_user_id
from app.content.dsa_schemas import SolvedProblemCreate
from database.db import get_session
from database.models.dsa import SolvedProblem

router = APIRouter(prefix="/api/dsa", tags=["dsa"])


@router.get("/solved", response_model=list[str])
def list_solved(
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    rows = session.exec(
        select(SolvedProblem).where(SolvedProblem.user_id == int(user_id))
    ).all()
    return [row.slug for row in rows]


@router.post("/solved", status_code=status.HTTP_204_NO_CONTENT)
def mark_solved(
    payload: SolvedProblemCreate,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    existing = session.exec(
        select(SolvedProblem)
        .where(SolvedProblem.user_id == int(user_id))
        .where(SolvedProblem.slug == payload.slug)
    ).first()
    if existing is None:
        session.add(SolvedProblem(user_id=int(user_id), slug=payload.slug))
        session.commit()


@router.delete("/solved/{slug}", status_code=status.HTTP_204_NO_CONTENT)
def unmark_solved(
    slug: str,
    user_id: str = Depends(get_current_user_id),
    session: Session = Depends(get_session),
):
    existing = session.exec(
        select(SolvedProblem)
        .where(SolvedProblem.user_id == int(user_id))
        .where(SolvedProblem.slug == slug)
    ).first()
    if existing is not None:
        session.delete(existing)
        session.commit()
