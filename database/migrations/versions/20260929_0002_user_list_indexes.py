"""composite indexes for per-user sorted lists

GET /api/interview filters interview_sessions by user_id and orders by
started_at DESC; GET /api/quiz/history does the same on quiz_results with
completed_at. The existing single-column user_id indexes still leave SQLite
sorting every matching row in a temp B-tree; (user_id, <timestamp>) lets it
walk the index in order instead.

Revision ID: 0002_user_list_indexes
Revises: 0001_baseline
Create Date: 2026-09-29 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
import sqlmodel


# revision identifiers, used by Alembic.
revision: str = "0002_user_list_indexes"
down_revision: Union[str, Sequence[str], None] = "0001_baseline"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("interview_sessions", schema=None) as batch_op:
        batch_op.create_index(
            "ix_interview_sessions_user_started", ["user_id", "started_at"], unique=False
        )

    with op.batch_alter_table("quiz_results", schema=None) as batch_op:
        batch_op.create_index(
            "ix_quiz_results_user_completed", ["user_id", "completed_at"], unique=False
        )


def downgrade() -> None:
    with op.batch_alter_table("quiz_results", schema=None) as batch_op:
        batch_op.drop_index("ix_quiz_results_user_completed")

    with op.batch_alter_table("interview_sessions", schema=None) as batch_op:
        batch_op.drop_index("ix_interview_sessions_user_started")
