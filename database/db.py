import os

from sqlmodel import Session, SQLModel, create_engine

# The database package configures itself from the environment so it stays
# independent of the backend app. The default matches the committed backend
# `.env`; Fly sets DATABASE_URL to the mounted volume path.
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./placement_prep.db")

# check_same_thread=False is required for SQLite across FastAPI's threaded
# request handlers; it's a SQLite-only arg, so only apply it there.
_connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

engine = create_engine(DATABASE_URL, echo=False, connect_args=_connect_args)


#: Columns added to tables that already exist in deployed databases.
#: `create_all` creates missing *tables* but never alters an existing one, and
#: there's no migrations framework here — so new **nullable** columns are listed
#: and added by hand. Existing rows keep NULL, which every reader must tolerate.
_ADDED_COLUMNS: dict[str, dict[str, str]] = {
    "interview_sessions": {
        # Which round the session is running (see InterviewMode). NULL on rows
        # predating modes; those are treated as the general interview.
        "mode": "VARCHAR",
        # JSON blob of the resume-derived context the round was started with,
        # so follow-up turns can be prompted with the same material.
        "context_json": "VARCHAR",
    },
}


def init_db() -> None:
    """Create all tables. Called once on application startup.

    Importing the models module registers every table on `SQLModel.metadata`
    before `create_all` runs.
    """
    from database import models  # noqa: F401  (populates SQLModel.metadata)

    SQLModel.metadata.create_all(engine)
    _add_missing_columns()


def _add_missing_columns() -> None:
    """Brings an existing SQLite file up to date with `_ADDED_COLUMNS`.

    Idempotent: each column is only added when `PRAGMA table_info` says it's
    absent, so this is safe to run on every startup.
    """
    if not DATABASE_URL.startswith("sqlite"):
        return

    with engine.connect() as connection:
        for table, columns in _ADDED_COLUMNS.items():
            info = connection.exec_driver_sql(f"PRAGMA table_info({table})").fetchall()
            if not info:
                continue  # table didn't exist, so create_all just made it correctly
            existing = {row[1] for row in info}
            for name, column_type in columns.items():
                if name not in existing:
                    connection.exec_driver_sql(
                        f"ALTER TABLE {table} ADD COLUMN {name} {column_type}"
                    )
        connection.commit()


def get_session():
    """FastAPI dependency that yields a DB session per-request."""
    with Session(engine) as session:
        yield session
