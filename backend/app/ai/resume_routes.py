from dataclasses import asdict

from fastapi import APIRouter, Depends

from app.auth.jwt import get_current_user_id
from app.ai.llm_service import generate_resume_review
from app.ai.resume_checks import DeviceFacts, analyse, checks, drop_repeats, hard_failures
from app.ai.schemas import (
    ResumeCheck,
    ResumeFactor,
    ResumeImprovement,
    ResumeReviewRequest,
    ResumeReviewResponse,
    ResumeRewrite,
)

router = APIRouter(prefix="/api/resume", tags=["resume"])


@router.post("/review", response_model=ResumeReviewResponse)
def review_resume(
    payload: ResumeReviewRequest,
    user_id: str = Depends(get_current_user_id),
):
    device = DeviceFacts(**payload.device.model_dump())
    signals = analyse(payload.resume_text)
    failures = hard_failures(signals, device)

    review = generate_resume_review(
        payload.target_role,
        payload.resume_text,
        signals,
        device,
        [failure["issue"] for failure in failures],
    )

    return ResumeReviewResponse(
        overall=review.overall,
        factors=[ResumeFactor(**factor._asdict()) for factor in review.factors],
        checks=[ResumeCheck(**asdict(check)) for check in checks(signals, device)],
        strengths=review.strengths,
        improvements=[
            ResumeImprovement(**item)
            for item in failures + drop_repeats(review.improvements, failures)
        ],
        rewrites=[ResumeRewrite(**rewrite) for rewrite in review.rewrites],
    )
