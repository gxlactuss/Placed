from pydantic import BaseModel


class DSAQuestion(BaseModel):
    title: str
    leetcode_url: str
    difficulty: str
    frequency: float | None = None  # how often this company asks it, if known


class CompanySummary(BaseModel):
    slug: str
    name: str
    question_count: int


class CompanyQuestionList(BaseModel):
    slug: str
    name: str
    questions: list[DSAQuestion]
