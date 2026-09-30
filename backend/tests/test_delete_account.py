import os
import tempfile
import unittest
from unittest import mock

from fastapi.testclient import TestClient
from sqlmodel import Session, SQLModel, create_engine, select

import database.db as db
from app.auth.jwt import create_access_token, hash_password
from app.auth.routes import _tables_owned_by_users
from app.core.config import settings
from app.core.rate_limit import limiter, reset_rate_limits
from app.main import app
from database.models import InterviewSession, QuizResult, SolvedProblem, User

# Every model with a user_id column. If a new per-user table is added, add it
# here too; test_every_user_table_is_covered fails until you do.
USER_OWNED_MODELS = (QuizResult, SolvedProblem, InterviewSession)


class DeleteAccountTests(unittest.TestCase):

    def setUp(self):
        handle, self.path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        url = f"sqlite:///{self.path}"
        self.engine = create_engine(url, connect_args={"check_same_thread": False})
        self.patches = [
            mock.patch.object(db, "engine", self.engine),
            mock.patch.object(db, "DATABASE_URL", url),
            mock.patch.object(limiter, "enabled", True),
            mock.patch.object(settings, "rate_limit_delete_account", "5/hour"),
        ]
        for patch in self.patches:
            patch.start()
        reset_rate_limits()

    def tearDown(self):
        reset_rate_limits()
        for patch in self.patches:
            patch.stop()
        self.engine.dispose()
        os.remove(self.path)

    def _make_user_with_data(self, email: str) -> tuple[int, dict]:
        with Session(self.engine) as session:
            user = User(email=email, hashed_password=hash_password("password123"))
            session.add(user)
            session.commit()
            session.refresh(user)
            user_id = user.id
            session.add(
                QuizResult(
                    user_id=user_id,
                    quiz_id="arrays-1",
                    total_questions=10,
                    correct_answers=7,
                    score_percentage=70,
                )
            )
            session.add(SolvedProblem(user_id=user_id, slug="two-sum"))
            session.add(InterviewSession(user_id=user_id, target_role="iOS Engineer"))
            session.commit()
        return user_id, {"Authorization": f"Bearer {create_access_token(str(user_id))}"}

    def _counts(self, user_id: int) -> dict[str, int]:
        with Session(self.engine) as session:
            counts = {
                model.__tablename__: len(
                    session.exec(select(model).where(model.user_id == user_id)).all()
                )
                for model in USER_OWNED_MODELS
            }
            counts["users"] = 1 if session.get(User, user_id) else 0
        return counts

    def test_every_user_table_is_covered(self):
        owned = {table.name for table in _tables_owned_by_users()}
        with_user_id = {
            table.name
            for table in SQLModel.metadata.sorted_tables
            if "user_id" in table.c
        }
        expected = {model.__tablename__ for model in USER_OWNED_MODELS}
        self.assertEqual(owned, expected)
        self.assertEqual(with_user_id, expected)

    def test_delete_removes_the_user_and_all_their_rows_only(self):
        with TestClient(app) as client:
            alice_id, alice = self._make_user_with_data("alice@example.com")
            bob_id, bob = self._make_user_with_data("bob@example.com")
            everything = {"users": 1, **{m.__tablename__: 1 for m in USER_OWNED_MODELS}}
            self.assertEqual(self._counts(alice_id), everything)

            response = client.delete("/api/auth/me", headers=alice)

            self.assertEqual(response.status_code, 204)
            self.assertEqual(response.content, b"")
            self.assertEqual(self._counts(alice_id), {k: 0 for k in everything})
            self.assertEqual(self._counts(bob_id), everything)

            # The deleted user's token no longer authenticates anywhere.
            me = client.get("/api/auth/me", headers=alice)
            self.assertEqual(me.status_code, 401)
            self.assertEqual(me.headers.get("www-authenticate"), "Bearer")
            self.assertEqual(client.get("/api/quiz/history", headers=alice).status_code, 401)
            self.assertEqual(client.delete("/api/auth/me", headers=alice).status_code, 401)

            # Bob is unaffected.
            self.assertEqual(client.get("/api/auth/me", headers=bob).status_code, 200)

    def test_unauthenticated_delete_is_rejected(self):
        with TestClient(app) as client:
            self._make_user_with_data("alice@example.com")

            self.assertEqual(client.delete("/api/auth/me").status_code, 401)
            bad = {"Authorization": "Bearer not-a-token"}
            self.assertEqual(client.delete("/api/auth/me", headers=bad).status_code, 401)

        with Session(self.engine) as session:
            self.assertEqual(len(session.exec(select(User)).all()), 1)

    def test_failure_midway_rolls_back_and_attempts_are_rate_limited_per_user(self):
        # A successful delete makes the next call 401 before the limiter runs, so
        # use a deletion that fails after the first table to exercise both the
        # single transaction and the per-user bucket.
        from sqlalchemy import delete as sa_delete

        calls = []

        def flaky_delete(table):
            calls.append(table)
            if len(calls) == 2:
                raise RuntimeError("boom")
            return sa_delete(table)

        with mock.patch.object(settings, "rate_limit_delete_account", "1/hour"):
            with TestClient(app, raise_server_exceptions=False) as client:
                alice_id, alice = self._make_user_with_data("alice@example.com")
                _, bob = self._make_user_with_data("bob@example.com")
                before = self._counts(alice_id)

                with mock.patch("app.auth.routes.delete", side_effect=flaky_delete), \
                        self.assertLogs("app.errors", "ERROR"):
                    failed = client.delete("/api/auth/me", headers=alice)
                self.assertEqual(failed.status_code, 500)
                self.assertEqual(self._counts(alice_id), before)

                again = client.delete("/api/auth/me", headers=alice)
                self.assertEqual(again.status_code, 429)
                self.assertIn("Too many account deletion attempts", again.json()["detail"])
                self.assertIn("Retry-After", again.headers)
                self.assertEqual(self._counts(alice_id), before)

                # Bob has his own bucket.
                self.assertEqual(client.delete("/api/auth/me", headers=bob).status_code, 204)


if __name__ == "__main__":
    unittest.main()
