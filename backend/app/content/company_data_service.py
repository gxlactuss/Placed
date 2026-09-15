from functools import lru_cache
from pathlib import Path

from app.content.company_schemas import CompanyQuestionList, CompanySummary

DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data" / "companies"


@lru_cache(maxsize=1)
def list_companies() -> list[CompanySummary]:
    raise NotImplementedError("Ingest company JSON files under backend/data/companies/")


def get_company_questions(slug: str) -> CompanyQuestionList:
    raise NotImplementedError("Load and parse the company's question JSON file")
