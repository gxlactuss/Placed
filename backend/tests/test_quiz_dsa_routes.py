"""Route tests for /api/quiz (submit, summary) and /api/dsa/solved.

/api/quiz/history paging/ordering and /api/quiz/progress best-score are
covered in test_pagination.py and are not repeated here.
"""

import os
import tempfile
import unittest
from unittest import mock

from fastapi.testclient import TestClient
from sqlmodel import Session, create_engine, select

import database.db as db
from app.ai.llm_service import QuizSummary
from app.auth.jwt import create_access_token, hash_password
from app.core.rate_limit import reset_rate_limits
from app.main import app
from database.models.dsa import SolvedProblem
from database.models.quiz import QuizResult
from database.models.user import User


def _submission(**overrides) -> dict:
    body = {
        "quiz_id": "arrays-basics",
        "total_questions": 10,
        "correct_answers": 7,
        "score_percentage": 70,
    }
    body.update(overrides)
    return body


def _summary_request(**overrides) -> dict:
    body = {
        "quiz_title": "Arrays Basics",
        "subject": "DSA",
        "score_percentage": 60,
        "correct_count": 6,
        "total_questions": 10,
        "missed": [
            {
                "prompt": "What is the time complexity of binary search?",
                "chosen_text": "O(n)",
                "correct_text": "O(log n)",
                "concept": "binary search",
            }
        ],
    }
    body.update(overrides)
    return body


def _missed_item(i: int) -> dict:
    return {"prompt": f"Question {i}", "chosen_text": None, "correct_text": "Answer"}


class QuizDSARouteTests(unittest.TestCase):

    def setUp(self):
        reset_rate_limits()
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
        self.user_a = self._make_user("a@example.com")
        self.user_b = self._make_user("b@example.com")
        self.headers_a = self._headers(self.user_a)
        self.headers_b = self._headers(self.user_b)

    def tearDown(self):
        self.client_cm.__exit__(None, None, None)
        for patch in self.patches:
            patch.stop()
        self.engine.dispose()
        os.remove(self.path)
        reset_rate_limits()

    def _make_user(self, email: str) -> int:
        with Session(self.engine) as session:
            user = User(email=email, hashed_password=hash_password("password123"))
            session.add(user)
            session.commit()
            session.refresh(user)
            return user.id

    @staticmethod
    def _headers(user_id: int) -> dict:
        return {"Authorization": f"Bearer {create_access_token(str(user_id))}"}

    def _solved_rows(self, user_id: int) -> list[SolvedProblem]:
        with Session(self.engine) as session:
            return session.exec(
                select(SolvedProblem).where(SolvedProblem.user_id == user_id)
            ).all()

    def _mark(self, slug: str, headers: dict):
        return self.client.post("/api/dsa/solved", json={"slug": slug}, headers=headers)

    # ---- POST /api/quiz/submit -------------------------------------------

    def test_submit_stores_row_for_caller_and_returns_it(self):
        response = self.client.post(
            "/api/quiz/submit", json=_submission(), headers=self.headers_a
        )
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["quiz_id"], "arrays-basics")
        self.assertEqual(body["total_questions"], 10)
        self.assertEqual(body["correct_answers"], 7)
        self.assertEqual(body["score_percentage"], 70)
        self.assertIsInstance(body["id"], int)
        self.assertTrue(body["completed_at"])
        self.assertNotIn("user_id", body)

        with Session(self.engine) as session:
            rows = session.exec(select(QuizResult)).all()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0].id, body["id"])
        self.assertEqual(rows[0].user_id, self.user_a)
        self.assertEqual(rows[0].quiz_id, "arrays-basics")

    def test_submit_missing_fields_is_422_with_string_detail(self):
        cases = [{}]
        for field in ("quiz_id", "total_questions", "correct_answers", "score_percentage"):
            body = _submission()
            del body[field]
            cases.append(body)
        for body in cases:
            response = self.client.post("/api/quiz/submit", json=body, headers=self.headers_a)
            self.assertEqual(response.status_code, 422, body)
            self.assertIsInstance(response.json()["detail"], str, body)

        with Session(self.engine) as session:
            self.assertEqual(session.exec(select(QuizResult)).all(), [])

    def test_submit_wrong_type_is_422(self):
        response = self.client.post(
            "/api/quiz/submit",
            json=_submission(score_percentage="lots"),
            headers=self.headers_a,
        )
        self.assertEqual(response.status_code, 422)
        self.assertIsInstance(response.json()["detail"], str)

    def test_submitted_rows_are_scoped_per_user(self):
        self.client.post(
            "/api/quiz/submit", json=_submission(quiz_id="a-quiz"), headers=self.headers_a
        )
        self.client.post(
            "/api/quiz/submit", json=_submission(quiz_id="b-quiz"), headers=self.headers_b
        )

        history_a = self.client.get("/api/quiz/history", headers=self.headers_a).json()
        history_b = self.client.get("/api/quiz/history", headers=self.headers_b).json()
        self.assertEqual([r["quiz_id"] for r in history_a], ["a-quiz"])
        self.assertEqual([r["quiz_id"] for r in history_b], ["b-quiz"])

        progress_b = self.client.get("/api/quiz/progress", headers=self.headers_b).json()
        self.assertEqual([p["quiz_id"] for p in progress_b], ["b-quiz"])

    def test_submit_rejects_out_of_range_scores(self):
        # An out-of-range score would otherwise win /api/quiz/progress's MAX forever.
        for body in (
            _submission(score_percentage=500),
            _submission(score_percentage=-1),
            _submission(total_questions=0),
            _submission(correct_answers=-3),
            _submission(total_questions=5, correct_answers=6),
            _submission(quiz_id=""),
        ):
            response = self.client.post("/api/quiz/submit", json=body, headers=self.headers_a)
            self.assertEqual(response.status_code, 422, body)

    # ---- POST /api/quiz/summary ------------------------------------------

    def test_summary_returns_generated_summary_and_focus(self):
        fake = QuizSummary(summary="Solid on basics.", focus=["binary search", "two pointers"])
        with mock.patch(
            "app.content.quiz_routes.generate_quiz_summary", return_value=fake
        ) as generate:
            response = self.client.post(
                "/api/quiz/summary", json=_summary_request(), headers=self.headers_a
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {"summary": "Solid on basics.", "focus": ["binary search", "two pointers"]},
        )
        generate.assert_called_once()
        kwargs = generate.call_args.kwargs
        self.assertEqual(kwargs["quiz_title"], "Arrays Basics")
        self.assertEqual(kwargs["score_percentage"], 60)
        self.assertEqual(kwargs["total_questions"], 10)
        self.assertEqual(kwargs["missed"][0]["correct_text"], "O(log n)")

    def test_summary_request_bounds_are_422(self):
        cases = {
            "score over 100": _summary_request(score_percentage=101),
            "negative score": _summary_request(score_percentage=-1),
            "zero questions": _summary_request(total_questions=0),
            "too many missed": _summary_request(missed=[_missed_item(i) for i in range(41)]),
            "missing title": {k: v for k, v in _summary_request().items() if k != "quiz_title"},
        }
        with mock.patch("app.content.quiz_routes.generate_quiz_summary") as generate:
            for name, body in cases.items():
                response = self.client.post(
                    "/api/quiz/summary", json=body, headers=self.headers_a
                )
                self.assertEqual(response.status_code, 422, name)
                self.assertIsInstance(response.json()["detail"], str, name)
            generate.assert_not_called()

    def test_summary_accepts_exactly_40_missed(self):
        fake = QuizSummary(summary="ok", focus=[])
        with mock.patch("app.content.quiz_routes.generate_quiz_summary", return_value=fake):
            response = self.client.post(
                "/api/quiz/summary",
                json=_summary_request(missed=[_missed_item(i) for i in range(40)]),
                headers=self.headers_a,
            )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"summary": "ok", "focus": []})

    # ---- /api/dsa/solved ---------------------------------------------------

    def test_mark_solved_adds_and_lists(self):
        response = self._mark("two-sum", self.headers_a)
        self.assertEqual(response.status_code, 204)
        self.assertEqual(response.content, b"")

        listed = self.client.get("/api/dsa/solved", headers=self.headers_a)
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.json(), ["two-sum"])

    def test_marking_same_slug_twice_keeps_one_row(self):
        self.assertEqual(self._mark("two-sum", self.headers_a).status_code, 204)
        self.assertEqual(self._mark("two-sum", self.headers_a).status_code, 204)

        self.assertEqual(len(self._solved_rows(self.user_a)), 1)
        listed = self.client.get("/api/dsa/solved", headers=self.headers_a).json()
        self.assertEqual(listed, ["two-sum"])

    def test_list_solved_returns_only_callers_slugs(self):
        self._mark("two-sum", self.headers_a)
        self._mark("valid-parentheses", self.headers_a)
        self._mark("lru-cache", self.headers_b)

        slugs_a = self.client.get("/api/dsa/solved", headers=self.headers_a).json()
        slugs_b = self.client.get("/api/dsa/solved", headers=self.headers_b).json()
        self.assertEqual(sorted(slugs_a), ["two-sum", "valid-parentheses"])
        self.assertEqual(slugs_b, ["lru-cache"])

    def test_list_solved_empty_for_new_user(self):
        response = self.client.get("/api/dsa/solved", headers=self.headers_a)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), [])

    def test_same_slug_can_be_solved_by_two_users(self):
        self.assertEqual(self._mark("two-sum", self.headers_a).status_code, 204)
        self.assertEqual(self._mark("two-sum", self.headers_b).status_code, 204)
        self.assertEqual(len(self._solved_rows(self.user_a)), 1)
        self.assertEqual(len(self._solved_rows(self.user_b)), 1)

    def test_unmark_removes_slug(self):
        self._mark("two-sum", self.headers_a)
        self._mark("valid-parentheses", self.headers_a)

        response = self.client.delete("/api/dsa/solved/two-sum", headers=self.headers_a)
        self.assertEqual(response.status_code, 204)
        listed = self.client.get("/api/dsa/solved", headers=self.headers_a).json()
        self.assertEqual(listed, ["valid-parentheses"])

    def test_unmark_missing_slug_is_204(self):
        response = self.client.delete("/api/dsa/solved/never-solved", headers=self.headers_a)
        self.assertEqual(response.status_code, 204)
        self.assertEqual(self._solved_rows(self.user_a), [])

    def test_unmark_does_not_touch_other_users_rows(self):
        self._mark("two-sum", self.headers_a)

        response = self.client.delete("/api/dsa/solved/two-sum", headers=self.headers_b)
        self.assertEqual(response.status_code, 204)
        self.assertEqual(
            self.client.get("/api/dsa/solved", headers=self.headers_a).json(), ["two-sum"]
        )

    def test_mark_solved_missing_slug_is_422(self):
        for body in ({}, {"slug": None}, {"slug": 42}):
            response = self.client.post("/api/dsa/solved", json=body, headers=self.headers_a)
            self.assertEqual(response.status_code, 422, body)
            self.assertIsInstance(response.json()["detail"], str, body)
        self.assertEqual(self._solved_rows(self.user_a), [])

    def test_mark_solved_rejects_empty_slug(self):
        # An empty slug could never be removed: DELETE /api/dsa/solved/{slug} has no URL for it.
        response = self._mark("", self.headers_a)
        self.assertEqual(response.status_code, 422)

    def test_mark_solved_rejects_unbounded_slug(self):
        # Every GET /api/dsa/solved would echo an unbounded slug back.
        response = self._mark("x" * 100_000, self.headers_a)
        self.assertEqual(response.status_code, 422)

    # ---- auth ------------------------------------------------------------

    def test_every_endpoint_requires_a_token(self):
        calls = [
            ("post", "/api/quiz/submit", _submission()),
            ("post", "/api/quiz/summary", _summary_request()),
            ("get", "/api/quiz/history", None),
            ("get", "/api/quiz/progress", None),
            ("get", "/api/dsa/solved", None),
            ("post", "/api/dsa/solved", {"slug": "two-sum"}),
            ("delete", "/api/dsa/solved/two-sum", None),
        ]
        bad_headers = [None, {"Authorization": "Bearer not-a-real-token"}]
        with mock.patch("app.content.quiz_routes.generate_quiz_summary") as generate:
            for method, path, body in calls:
                for headers in bad_headers:
                    kwargs = {"headers": headers} if headers else {}
                    if body is not None:
                        kwargs["json"] = body
                    response = getattr(self.client, method)(path, **kwargs)
                    self.assertEqual(response.status_code, 401, (method, path, headers))
            generate.assert_not_called()

        with Session(self.engine) as session:
            self.assertEqual(session.exec(select(QuizResult)).all(), [])
            self.assertEqual(session.exec(select(SolvedProblem)).all(), [])


if __name__ == "__main__":
    unittest.main()
