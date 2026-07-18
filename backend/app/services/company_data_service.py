"""
Loads company-wise DSA question data sourced from:
https://github.com/liquidslr/leetcode-company-wise-problems

Expected on-disk layout (populate via a one-time ingestion script, not at
request time):
    backend/data/companies/<company-slug>.json
    -> {"name": "Google", "questions": [{"title": ..., "leetcode_url": ..., "difficulty": ..., "frequency": ...}]}
"""

from functools import lru_cache
from pathlib import Path

from app.schemas.company import CompanyQuestionList, CompanySummary

DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data" / "companies"


@lru_cache(maxsize=1)
def list_companies() -> list[CompanySummary]:
    # TODO: read each JSON file under DATA_DIR and build the summary list
    raise NotImplementedError("Ingest company JSON files under backend/data/companies/")


def get_company_questions(slug: str) -> CompanyQuestionList:
    # TODO: load backend/data/companies/{slug}.json and map to CompanyQuestionList
    raise NotImplementedError("Load and parse the company's question JSON file")
