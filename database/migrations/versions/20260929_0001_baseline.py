"""baseline schema

The full schema as it stood when Alembic was introduced (users, quiz_results,
solved_problems, interview_sessions, including users.target_company and
interview_sessions.mode/context_json).

Every CREATE uses IF NOT EXISTS so this revision also adopts pre-Alembic
databases: init_db() first adds the legacy hand-migrated columns, then runs
this revision, which fills in any table or index the old create_all/ALTER code
never produced (e.g. ix_interview_sessions_mode) and records the version.
Later revisions must NOT use this trick — they run against a known schema.

Revision ID: 0001_baseline
Revises:
Create Date: 2026-09-29 17:22:59.696891

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import sqlmodel


# revision identifiers, used by Alembic.
revision: str = "0001_baseline"
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("email", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("hashed_password", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("full_name", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.Column("target_role", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.Column("target_company", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.Column("is_verified", sa.Boolean(), nullable=False),
        sa.Column("verification_code", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.Column("verification_code_expires_at", sa.DateTime(), nullable=True),
        sa.Column("onboarded", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        if_not_exists=True,
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True, if_not_exists=True)

    op.create_table(
        "interview_sessions",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("target_role", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("mode", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.Column("context_json", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.Column(
            "status",
            sa.Enum("IN_PROGRESS", "COMPLETED", "ABANDONED", name="interviewstatus"),
            nullable=False,
        ),
        sa.Column("transcript_json", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("overall_feedback", sqlmodel.sql.sqltypes.AutoString(), nullable=True),
        sa.Column("started_at", sa.DateTime(), nullable=False),
        sa.Column("ended_at", sa.DateTime(), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        if_not_exists=True,
    )
    op.create_index(
        "ix_interview_sessions_mode", "interview_sessions", ["mode"], unique=False, if_not_exists=True
    )
    op.create_index(
        "ix_interview_sessions_user_id", "interview_sessions", ["user_id"], unique=False, if_not_exists=True
    )

    op.create_table(
        "quiz_results",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("quiz_id", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("total_questions", sa.Integer(), nullable=False),
        sa.Column("correct_answers", sa.Integer(), nullable=False),
        sa.Column("score_percentage", sa.Integer(), nullable=False),
        sa.Column("completed_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        if_not_exists=True,
    )
    op.create_index("ix_quiz_results_quiz_id", "quiz_results", ["quiz_id"], unique=False, if_not_exists=True)
    op.create_index("ix_quiz_results_user_id", "quiz_results", ["user_id"], unique=False, if_not_exists=True)

    op.create_table(
        "solved_problems",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("user_id", sa.Integer(), nullable=False),
        sa.Column("slug", sqlmodel.sql.sqltypes.AutoString(), nullable=False),
        sa.Column("solved_at", sa.DateTime(), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("user_id", "slug", name="uq_solved_user_slug"),
        if_not_exists=True,
    )
    op.create_index("ix_solved_problems_slug", "solved_problems", ["slug"], unique=False, if_not_exists=True)
    op.create_index(
        "ix_solved_problems_user_id", "solved_problems", ["user_id"], unique=False, if_not_exists=True
    )


def downgrade() -> None:
    op.drop_table("solved_problems")
    op.drop_table("quiz_results")
    op.drop_table("interview_sessions")
    op.drop_table("users")
