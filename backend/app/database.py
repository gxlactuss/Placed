from sqlmodel import SQLModel, Session, create_engine

from app.core.config import settings

# check_same_thread=False is required for SQLite when accessed across
# FastAPI's threaded request handlers.
engine = create_engine(
    settings.database_url,
    echo=False,
    connect_args={"check_same_thread": False},
)


def init_db() -> None:
    """Create all tables. Called once on application startup."""
    SQLModel.metadata.create_all(engine)


def get_session():
    """FastAPI dependency that yields a DB session per-request."""
    with Session(engine) as session:
        yield session
