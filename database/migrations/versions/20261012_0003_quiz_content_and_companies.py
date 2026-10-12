"""quiz content and company models

Revision ID: 0003_quiz_content_and_companies
Revises: 0002_user_list_indexes
Create Date: 2026-10-12 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import sqlmodel


# revision identifiers, used by Alembic.
revision: str = "0003_quiz_content_and_companies"
down_revision: Union[str, Sequence[str], None] = "0002_user_list_indexes"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "Company",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("slug", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("name", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("is_partner_recruiter", sa.Boolean(), nullable=False, server_default=sa.text("0")),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("slug", name="uq_company_slug"),
    )
    op.create_index("ix_Company_slug", "Company", ["slug"], unique=True)

    op.create_table(
        "Problem",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("slug", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("title", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("difficulty", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("url", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("slug", name="uq_problem_slug"),
    )
    op.create_index("ix_Problem_slug", "Problem", ["slug"], unique=True)

    op.create_table(
        "CompanyProblem",
        sa.Column("company_id", sa.Integer(), nullable=False),
        sa.Column("problem_id", sa.Integer(), nullable=False),
        sa.Column("topics", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.ForeignKeyConstraint(["company_id"], ["Company.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["problem_id"], ["Problem.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("company_id", "problem_id"),
    )
    op.create_index(
        "idx_company_problem_problem_id", "CompanyProblem", ["problem_id"], unique=False
    )

    op.create_table(
        "Quiz",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("slug", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("title", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("category", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.Column(
            "difficulty",
            sa.Enum("Easy", "Medium", "Hard", name="quizdifficulty"),
            nullable=False,
            server_default="Medium",
        ),
        sa.Column("questions_to_pass", sa.Integer(), nullable=True),
        sa.CheckConstraint("difficulty IN ('Easy', 'Medium', 'Hard')", name="ck_quiz_difficulty"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("slug", name="uq_quiz_slug"),
    )
    op.create_index("ix_Quiz_slug", "Quiz", ["slug"], unique=True)

    op.create_table(
        "Question",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("quiz_id", sa.Integer(), nullable=False),
        sa.Column("prompt", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.ForeignKeyConstraint(["quiz_id"], ["Quiz.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("idx_question_quiz_id", "Question", ["quiz_id"], unique=False)

    op.create_table(
        "Option",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("question_id", sa.Integer(), nullable=False),
        sa.Column("label", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.Column("text", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("is_correct", sa.Boolean(), nullable=False, server_default=sa.text("0")),
        sa.ForeignKeyConstraint(["question_id"], ["Question.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("idx_option_question_id", "Option", ["question_id"], unique=False)

    with op.batch_alter_table("quiz_results", schema=None) as batch_op:
        batch_op.add_column(sa.Column("score", sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column("submitted_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("quiz_results", schema=None) as batch_op:
        batch_op.drop_column("submitted_at")
        batch_op.drop_column("score")

    op.drop_table("Option")
    op.drop_table("Question")
    op.drop_table("Quiz")
    op.drop_table("CompanyProblem")
    op.drop_table("Problem")
    op.drop_table("Company")
