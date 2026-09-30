import json
import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

from fastapi.testclient import TestClient
from sqlmodel import Session, create_engine

import app.ai.routes as interview_routes
import database.db as db
from app.auth.jwt import create_access_token, hash_password
from app.main import app
from database.models.interview import InterviewSession
from database.models.quiz import QuizResult
from database.models.user import User

BASE = datetime(2026, 1, 1, tzinfo=timezone.utc)


class PaginationTests(unittest.TestCase):

    def setUp(self):
        handle, self.path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        url = f"sqlite:///{self.path}"
        self.engine = create_engine(url, connect_args={"check_same_thread": False})
        self.patches = [
            mock.patch.object(db, "engine", self.engine),
            mock.patch.object(db, "DATABASE_URL", url),
        ]
        for patch in self.patches:
            patch.start()
        self.client_cm = TestClient(app)
        self.client = self.client_cm.__enter__()
        self.user_id = self._make_user("a@example.com")
        self.other_id = self._make_user("b@example.com")
        self.headers = {"Authorization": f"Bearer {create_access_token(str(self.user_id))}"}

    def tearDown(self):
        self.client_cm.__exit__(None, None, None)
        for patch in self.patches:
            patch.stop()
        self.engine.dispose()
        os.remove(self.path)

    def _make_user(self, email: str) -> int:
        with Session(self.engine) as session:
            user = User(email=email, hashed_password=hash_password("password123"))
            session.add(user)
            session.commit()
            session.refresh(user)
            return user.id

    def _add(self, *rows) -> None:
        with Session(self.engine) as session:
            session.add_all(rows)
            session.commit()

    def _quiz(self, user_id: int, quiz_id: str, score: int, minutes: int) -> QuizResult:
        return QuizResult(
            user_id=user_id,
            quiz_id=quiz_id,
            total_questions=10,
            correct_answers=score // 10,
            score_percentage=score,
            completed_at=BASE + timedelta(minutes=minutes),
        )

    def _interview(self, user_id: int, answers: int, minutes: int) -> InterviewSession:
        transcript = [{"speaker": "ai", "text": "Q"}]
        transcript += [{"speaker": "user", "text": "A"}] * answers
        return InterviewSession(
            user_id=user_id,
            target_role=f"role-{minutes}",
            transcript_json=json.dumps(transcript),
            started_at=BASE + timedelta(minutes=minutes),
        )

    # /api/quiz/history

    def test_history_is_newest_first_and_paginated(self):
        self._add(
            *(self._quiz(self.user_id, f"q{i}", 50, minutes=i) for i in range(5)),
            self._quiz(self.other_id, "other", 90, minutes=100),
        )

        everything = self.client.get("/api/quiz/history", headers=self.headers)
        self.assertEqual(everything.status_code, 200)
        self.assertEqual([r["quiz_id"] for r in everything.json()], ["q4", "q3", "q2", "q1", "q0"])

        page = self.client.get("/api/quiz/history?limit=2&offset=1", headers=self.headers)
        self.assertEqual([r["quiz_id"] for r in page.json()], ["q3", "q2"])

        tail = self.client.get("/api/quiz/history?limit=2&offset=4", headers=self.headers)
        self.assertEqual([r["quiz_id"] for r in tail.json()], ["q0"])

    def test_history_ties_on_time_break_by_id_desc(self):
        self._add(self._quiz(self.user_id, "first", 50, 0))
        self._add(self._quiz(self.user_id, "second", 50, 0))
        response = self.client.get("/api/quiz/history", headers=self.headers)
        self.assertEqual([r["quiz_id"] for r in response.json()], ["second", "first"])

    def test_history_rejects_out_of_range_params(self):
        for query in ("limit=0", "limit=201", "offset=-1"):
            response = self.client.get(f"/api/quiz/history?{query}", headers=self.headers)
            self.assertEqual(response.status_code, 422, query)

    # /api/quiz/progress

    def test_progress_returns_best_score_per_quiz(self):
        self._add(
            self._quiz(self.user_id, "arrays", 40, 0),
            self._quiz(self.user_id, "arrays", 80, 1),
            self._quiz(self.user_id, "arrays", 60, 2),
            self._quiz(self.user_id, "graphs", 30, 3),
            self._quiz(self.other_id, "arrays", 100, 4),
        )
        response = self.client.get("/api/quiz/progress", headers=self.headers)
        self.assertEqual(response.status_code, 200)
        best = {item["quiz_id"]: item["best_score"] for item in response.json()}
        self.assertEqual(best, {"arrays": 80, "graphs": 30})

    # /api/interview

    def test_interview_list_skips_empty_sessions_without_gaps(self):
        # 12 sessions, minute i; every third one has no answers.
        rows = [self._interview(self.user_id, 0 if i % 3 == 0 else 1, i) for i in range(12)]
        rows.append(self._interview(self.other_id, 2, 99))
        self._add(*rows)
        visible = [f"role-{i}" for i in reversed(range(12)) if i % 3 != 0]

        # A tiny scan batch forces the filtered pages to span several SQL batches.
        with mock.patch.object(interview_routes, "_INTERVIEW_SCAN_BATCH", 3):
            everything = self.client.get("/api/interview", headers=self.headers)
            self.assertEqual(everything.status_code, 200)
            self.assertEqual([s["target_role"] for s in everything.json()], visible)

            paged = []
            for offset in range(0, 10, 3):
                page = self.client.get(
                    f"/api/interview?limit=3&offset={offset}", headers=self.headers
                )
                self.assertEqual(page.status_code, 200)
                paged += [s["target_role"] for s in page.json()]
        self.assertEqual(paged, visible)

    def test_interview_list_keeps_summary_fields(self):
        self._add(self._interview(self.user_id, 2, 0))
        (summary,) = self.client.get("/api/interview", headers=self.headers).json()
        self.assertEqual(summary["answer_count"], 2)
        for key in ("id", "target_role", "mode", "company", "status", "rating",
                    "started_at", "ended_at"):
            self.assertIn(key, summary)

    def test_interview_list_rejects_out_of_range_params(self):
        for query in ("limit=0", "limit=201", "offset=-1"):
            response = self.client.get(f"/api/interview?{query}", headers=self.headers)
            self.assertEqual(response.status_code, 422, query)


if __name__ == "__main__":
    unittest.main()
