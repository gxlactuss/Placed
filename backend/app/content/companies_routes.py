from fastapi import APIRouter, Depends, HTTPException

from app.auth.jwt import get_current_user_id
from app.content.company_schemas import CompanyQuestionList, CompanySummary
from app.content.company_data_service import get_company_questions, list_companies

router = APIRouter(prefix="/api/companies", tags=["companies"])


@router.get("", response_model=list[CompanySummary])
def get_companies(user_id: str = Depends(get_current_user_id)):
    return list_companies()


@router.get("/{slug}", response_model=CompanyQuestionList)
def get_company(slug: str, user_id: str = Depends(get_current_user_id)):
    try:
        return get_company_questions(slug)
    except NotImplementedError:
        raise
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail=f"No question data for company '{slug}'")
