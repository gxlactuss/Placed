from pydantic import BaseModel


class SolvedProblemCreate(BaseModel):
    slug: str
