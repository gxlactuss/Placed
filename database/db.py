import os
from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import Connection, inspect
from sqlmodel import Session, create_engine

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./placement_prep.db")

_connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

engine = create_engine(DATABASE_URL, echo=False, connect_args=_connect_args)

ALEMBIC_INI = Path(__file__).resolve().parent / "alembic.ini"
BASELINE_REVISION = "0001_baseline"
_BASELINE_TABLES = {"users", "quiz_results", "solved_problems", "interview_sessions"}

# Columns the pre-Alembic startup code bolted on with ALTER TABLE. Frozen: only
# used to bring a legacy (unversioned) database up to the baseline revision.
_LEGACY_ADDED_COLUMNS: dict[str, dict[str, str]] = {
    "users": {
        "target_company": "VARCHAR",
    },
    "interview_sessions": {
        "mode": "VARCHAR",
        "context_json": "VARCHAR",
    },
}


def alembic_config(connection: Connection | None = None) -> Config:
    config = Config(str(ALEMBIC_INI))
    if connection is not None:
        config.attributes["connection"] = connection
    return config


def init_db() -> None:
    """Bring the database schema to the latest Alembic revision.

    - fresh database: every migration runs from scratch;
    - legacy database (our tables, no alembic_version): patched up to the
      baseline revision and recorded as such, then upgraded;
    - managed database: pending migrations (if any) run.
    """
    # `engine` is resolved at call time so tests can patch database.db.engine.
    with engine.begin() as connection:
        config = alembic_config(connection)
        tables = set(inspect(connection).get_table_names())
        if tables & _BASELINE_TABLES and "alembic_version" not in tables:
            _bootstrap_legacy_database(connection)
            # The baseline creates with IF NOT EXISTS, so on a legacy database it
            # only adds whatever tables/indexes are missing, then stamps itself.
            command.upgrade(config, BASELINE_REVISION)
        command.upgrade(config, "head")


def _bootstrap_legacy_database(connection: Connection) -> None:
    """One-off: add the columns the old ALTER TABLE code used to add."""
    inspector = inspect(connection)
    for table, columns in _LEGACY_ADDED_COLUMNS.items():
        if not inspector.has_table(table):
            continue
        existing = {column["name"] for column in inspector.get_columns(table)}
        for name, column_type in columns.items():
            if name not in existing:
                connection.exec_driver_sql(f"ALTER TABLE {table} ADD COLUMN {name} {column_type}")


def get_session():
    with Session(engine) as session:
        yield session
