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


def init_db() -> None:
    """Create all tables. Called once on application startup.

    Importing the models module registers every table on `SQLModel.metadata`
    before `create_all` runs.
    """
    from database import models  # noqa: F401  (populates SQLModel.metadata)

    SQLModel.metadata.create_all(engine)


def get_session():
    """FastAPI dependency that yields a DB session per-request."""
    with Session(engine) as session:
        yield session
