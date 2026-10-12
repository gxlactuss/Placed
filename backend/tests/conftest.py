import os
import pytest
from backend.tests.db_test_fixtures import get_in_memory_db

# Ensure JWT secret is set for tests
os.environ.setdefault("JWT_SECRET_KEY", "test-only-jwt-secret-not-for-real-use-0123456789")


@pytest.fixture
def memory_db():
    engine, conn = get_in_memory_db()
    try:
        yield conn
    finally:
        engine.dispose()


@pytest.fixture
def memory_engine():
    engine, conn = get_in_memory_db()
    try:
        yield engine
    finally:
        engine.dispose()
