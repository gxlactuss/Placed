import os

from sqlmodel import Session, SQLModel, create_engine

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./placement_prep.db")

_connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}

engine = create_engine(DATABASE_URL, echo=False, connect_args=_connect_args)

_ADDED_COLUMNS: dict[str, dict[str, str]] = {
    "interview_sessions": {
        "mode": "VARCHAR",
        "context_json": "VARCHAR",
    },
}


def init_db() -> None:
    from database import models

    SQLModel.metadata.create_all(engine)
    _add_missing_columns()


def _add_missing_columns() -> None:
    if not DATABASE_URL.startswith("sqlite"):
        return

    with engine.connect() as connection:
        for table, columns in _ADDED_COLUMNS.items():
            info = connection.exec_driver_sql(f"PRAGMA table_info({table})").fetchall()
            if not info:
                continue
            existing = {row[1] for row in info}
            for name, column_type in columns.items():
                if name not in existing:
                    connection.exec_driver_sql(
                        f"ALTER TABLE {table} ADD COLUMN {name} {column_type}"
                    )
        connection.commit()


def get_session():
    with Session(engine) as session:
        yield session
