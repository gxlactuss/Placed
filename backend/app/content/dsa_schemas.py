from pydantic import BaseModel, Field


class SolvedProblemCreate(BaseModel):
    # Bundled LeetCode slugs top out under 100 characters.
    slug: str = Field(min_length=1, max_length=200)
