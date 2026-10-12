from __future__ import annotations

import sqlite3
from typing import Generator, Tuple
import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, create_engine
from sqlalchemy.engine import Engine

import database.models  # noqa: F401


def create_in_memory_engine() -> Engine:
    """Create a thread-safe in-memory SQLite engine with foreign keys enabled."""
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    with engine.connect() as conn:
        conn.exec_driver_sql("PRAGMA foreign_keys = ON;")
    SQLModel.metadata.create_all(engine)
    return engine


def get_in_memory_db() -> Tuple[Engine, sqlite3.Connection]:
    """Return an in-memory engine and its raw sqlite3 connection with foreign keys enabled."""
    engine = create_in_memory_engine()
    raw_conn = engine.raw_connection().dbapi_connection
    raw_conn.execute("PRAGMA foreign_keys = ON;")
    return engine, raw_conn


@pytest.fixture
def memory_db() -> Generator[sqlite3.Connection, None, None]:
    """Pytest fixture providing an isolated in-memory SQLite database."""
    engine, conn = get_in_memory_db()
    try:
        yield conn
    finally:
        engine.dispose()
