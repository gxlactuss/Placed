from typing import Optional

import sqlalchemy as sa
from sqlmodel import Field, SQLModel


class Company(SQLModel, table=True):
    __tablename__ = "Company"

    id: Optional[int] = Field(default=None, primary_key=True)
    slug: str = Field(unique=True, index=True, nullable=False)
    name: str = Field(nullable=False)
    is_partner_recruiter: bool = Field(
        default=False,
        nullable=False,
        sa_column_kwargs={"server_default": sa.text("0")},
    )


class Problem(SQLModel, table=True):
    __tablename__ = "Problem"

    id: Optional[int] = Field(default=None, primary_key=True)
    slug: str = Field(unique=True, index=True, nullable=False)
    title: str = Field(nullable=False)
    difficulty: str = Field(nullable=False)
    url: Optional[str] = Field(default=None, nullable=True)


class CompanyProblem(SQLModel, table=True):
    __tablename__ = "CompanyProblem"

    company_id: int = Field(
        foreign_key="Company.id",
        primary_key=True,
        ondelete="CASCADE",
    )
    problem_id: int = Field(
        foreign_key="Problem.id",
        primary_key=True,
        ondelete="CASCADE",
    )
    topics: Optional[str] = Field(default=None, nullable=True)
