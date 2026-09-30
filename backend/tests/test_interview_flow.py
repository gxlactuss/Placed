"""The mock-interview session flow in app/ai/routes.py.

Every LLM / transcription call is mocked where routes.py imports it, so these
tests never touch the network. The list endpoint (test_pagination.py),
resume-summary (test_resume_privacy.py) and company context
(test_company_style.py / test_target_company.py) are covered elsewhere.
"""

import json
import os
import tempfile
import unittest
from unittest import mock

from fastapi.testclient import TestClient
from sqlmodel import Session, create_engine

import database.db as db
from app.ai.interview_difficulty import MIN_QUESTIONS, Assessment
from app.ai.llm_service import AnswerRubric, Feedback, FollowUp
from app.auth.jwt import create_access_token, hash_password
from app.core.config import settings
from app.core.rate_limit import reset_rate_limits
from app.main import app
from database.models.interview import InterviewSession, InterviewStatus
from database.models.user import User

ROUTES = "app.ai.routes"
OPENING = "Tell me how a hash map handles collisions."


def _follow_up(message="Good. Next: what is a B-tree?", complete=False, ended_early=False):
    return FollowUp(message, complete, ended_early, Assessment(accuracy=2, ease=1, topic="DS"))


def _feedback():
    scores = {"correctness": 7, "depth": 6, "structure": 8, "communication": 7, "confidence": 6}
    return Feedback(
        rating=7,
        summary="Solid fundamentals.",
        improvements=["Give concrete examples."],
        mistakes=["Confused B-tree with BST."],
        rubric=scores,
        answers=[AnswerRubric(answer=1, scores=scores, score=6.8, note="Clear.", level=3)],
    )


class InterviewFlowTests(unittest.TestCase):

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
        self.user_id = self._make_user("a@example.com")
        self.other_id = self._make_user("b@example.com")
        self.headers = self._headers(self.user_id)
        self.other_headers = self._headers(self.other_id)

    def tearDown(self):
        self.client_cm.__exit__(None, None, None)
        for patch in self.patches:
            patch.stop()
        self.engine.dispose()
        os.remove(self.path)
        reset_rate_limits()

    # -- helpers ---------------------------------------------------------

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

    def _load(self, session_id: int) -> InterviewSession:
        with Session(self.engine) as session:
            interview = session.get(InterviewSession, session_id)
            session.expunge(interview)
            return interview

    def _start(self, headers=None, **payload) -> dict:
        body = {"target_role": "Backend Engineer", "mode": "core_cs", **payload}
        with mock.patch(f"{ROUTES}.generate_first_question", return_value=OPENING):
            response = self.client.post(
                "/api/interview/start", json=body, headers=headers or self.headers
            )
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def _respond(self, session_id: int, answer="An answer.", follow_up=None, headers=None, **extra):
        with mock.patch(
            f"{ROUTES}.generate_follow_up", return_value=follow_up or _follow_up()
        ) as generator:
            response = self.client.post(
                "/api/interview/respond",
                json={"session_id": session_id, "transcribed_answer": answer, **extra},
                headers=headers or self.headers,
            )
        return response, generator

    # -- start -----------------------------------------------------------

    def test_start_creates_owned_session_with_opening_turn(self):
        with mock.patch(f"{ROUTES}.generate_first_question", return_value=OPENING) as generator:
            response = self.client.post(
                "/api/interview/start",
                json={"target_role": "Backend Engineer", "mode": "core_cs"},
                headers=self.headers,
            )
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertEqual(body["ai_message"], OPENING)
        self.assertFalse(body["is_follow_up"])
        self.assertFalse(body["interview_complete"])
        self.assertEqual(body["question_number"], 1)
        generator.assert_called_once()
        self.assertEqual(generator.call_args.args[0], "Backend Engineer")

        interview = self._load(body["session_id"])
        self.assertEqual(interview.user_id, self.user_id)
        self.assertEqual(interview.status, InterviewStatus.IN_PROGRESS)
        self.assertEqual(interview.mode, "core_cs")
        transcript = json.loads(interview.transcript_json)
        self.assertEqual(len(transcript), 1)
        self.assertEqual(transcript[0]["speaker"], "ai")
        self.assertEqual(transcript[0]["text"], OPENING)

    def test_start_with_unknown_mode_falls_back_to_core_cs(self):
        body = self._start(mode="not-a-mode")
        self.assertEqual(self._load(body["session_id"]).mode, "core_cs")

    # -- respond ---------------------------------------------------------

    def test_respond_appends_answer_and_next_question(self):
        session_id = self._start()["session_id"]
        response, generator = self._respond(
            session_id, answer="Chaining or open addressing.", think_seconds=3.14, speaking_seconds=20
        )
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertEqual(body["session_id"], session_id)
        self.assertEqual(body["ai_message"], "Good. Next: what is a B-tree?")
        self.assertTrue(body["is_follow_up"])
        self.assertFalse(body["interview_complete"])
        self.assertEqual(body["question_number"], 2)
        generator.assert_called_once()
        self.assertEqual(generator.call_args.args[4], "Chaining or open addressing.")

        interview = self._load(session_id)
        self.assertEqual(interview.status, InterviewStatus.IN_PROGRESS)
        transcript = json.loads(interview.transcript_json)
        self.assertEqual([t["speaker"] for t in transcript], ["ai", "user", "ai"])
        answer = transcript[1]
        self.assertEqual(answer["text"], "Chaining or open addressing.")
        self.assertEqual(answer["think_seconds"], 3.1)
        self.assertEqual(answer["speaking_seconds"], 20)
        self.assertEqual(answer["accuracy"], 2)
        self.assertEqual(answer["ease"], 1)
        self.assertEqual(transcript[2]["text"], "Good. Next: what is a B-tree?")

    def test_respond_to_another_users_session_is_404_and_untouched(self):
        session_id = self._start()["session_id"]
        before = self._load(session_id).transcript_json

        response, generator = self._respond(session_id, headers=self.other_headers)
        self.assertEqual(response.status_code, 404)
        generator.assert_not_called()
        self.assertEqual(self._load(session_id).transcript_json, before)

    def test_respond_to_unknown_session_is_404(self):
        response, generator = self._respond(999_999)
        self.assertEqual(response.status_code, 404)
        generator.assert_not_called()

    def test_respond_to_completed_session_is_409(self):
        session_id = self._start()["session_id"]
        self._respond(session_id, follow_up=_follow_up("Thanks, that's the round.", complete=True))
        before = self._load(session_id).transcript_json

        response, generator = self._respond(session_id)
        self.assertEqual(response.status_code, 409)
        generator.assert_not_called()
        self.assertEqual(self._load(session_id).transcript_json, before)

    def test_respond_to_abandoned_session_is_409(self):
        session_id = self._start()["session_id"]
        self._respond(session_id, follow_up=_follow_up("Stopping here.", complete=True, ended_early=True))
        response, _ = self._respond(session_id)
        self.assertEqual(response.status_code, 409)

    # -- full flow -------------------------------------------------------

    def test_full_flow_completes_when_follow_up_closes_the_round(self):
        session_id = self._start()["session_id"]
        rounds = 3
        for number in range(rounds):
            response, _ = self._respond(session_id, answer=f"Answer {number + 1}")
            self.assertEqual(response.status_code, 200, response.text)
            self.assertFalse(response.json()["interview_complete"])
            self.assertEqual(response.json()["question_number"], number + 2)
            self.assertEqual(self._load(session_id).status, InterviewStatus.IN_PROGRESS)

        response, _ = self._respond(
            session_id, answer="Final answer", follow_up=_follow_up("That's the round.", complete=True)
        )
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertTrue(body["interview_complete"])
        self.assertFalse(body["ended_early"])
        self.assertIsNone(body["question_number"])

        interview = self._load(session_id)
        self.assertEqual(interview.status, InterviewStatus.COMPLETED)
        self.assertIsNotNone(interview.ended_at)
        transcript = json.loads(interview.transcript_json)
        self.assertEqual(len(transcript), 1 + 2 * (rounds + 1))
        self.assertEqual(transcript[-2]["text"], "Final answer")
        self.assertEqual(transcript[-1]["speaker"], "ai")
        self.assertEqual(transcript[-1]["text"], "That's the round.")
        # The closing turn carries no next-question level/topic.
        self.assertNotIn("level", transcript[-1])

    def test_ending_early_marks_session_abandoned(self):
        session_id = self._start()["session_id"]
        response, _ = self._respond(
            session_id, follow_up=_follow_up("Stopping here.", complete=True, ended_early=True)
        )
        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(response.json()["interview_complete"])
        self.assertTrue(response.json()["ended_early"])
        interview = self._load(session_id)
        self.assertEqual(interview.status, InterviewStatus.ABANDONED)
        self.assertIsNotNone(interview.ended_at)

    def test_round_cannot_close_before_min_questions_end_to_end(self):
        """Real generate_follow_up with only the raw model call mocked.

        The model tries to close the round on every reply; the round stays open
        until MIN_QUESTIONS answers have been given, then closes.
        """
        closing_reply = "[[ASSESS accuracy=2 ease=1 topic=Hashing]]\nNice. That's the round.\n[[ROUND_COMPLETE]]"
        with mock.patch("app.ai.llm_service._generate", return_value=OPENING):
            session_id = self.client.post(
                "/api/interview/start",
                json={"target_role": "Backend Engineer", "mode": "core_cs"},
                headers=self.headers,
            ).json()["session_id"]

        with mock.patch("app.ai.llm_service._generate", return_value=closing_reply), \
                self.assertLogs("app.ai.llm_service", level="WARNING") as logs:
            for number in range(1, MIN_QUESTIONS + 1):
                response = self.client.post(
                    "/api/interview/respond",
                    json={"session_id": session_id, "transcribed_answer": f"Answer {number}"},
                    headers=self.headers,
                )
                self.assertEqual(response.status_code, 200, response.text)
                complete = response.json()["interview_complete"]
                self.assertEqual(complete, number >= MIN_QUESTIONS, f"after answer {number}")
                self.assertNotIn("[[", response.json()["ai_message"])
        kept_open = [r for r in logs.records if "keeping it open" in r.getMessage()]
        self.assertEqual(len(kept_open), MIN_QUESTIONS - 1)

        interview = self._load(session_id)
        self.assertEqual(interview.status, InterviewStatus.COMPLETED)
        answers = [t for t in json.loads(interview.transcript_json) if t["speaker"] == "user"]
        self.assertEqual(len(answers), MIN_QUESTIONS)

    # -- feedback --------------------------------------------------------

    def _post_feedback(self, session_id: int, headers=None):
        with mock.patch(f"{ROUTES}.generate_feedback", return_value=_feedback()) as generator:
            response = self.client.post(
                f"/api/interview/{session_id}/feedback", headers=headers or self.headers
            )
        return response, generator

    def test_feedback_is_generated_persisted_and_then_served_from_storage(self):
        session_id = self._start()["session_id"]
        self._respond(session_id, follow_up=_follow_up("That's the round.", complete=True))

        response, generator = self._post_feedback(session_id)
        self.assertEqual(response.status_code, 200, response.text)
        generator.assert_called_once()
        body = response.json()
        self.assertEqual(body["rating"], 7)
        self.assertEqual(body["summary"], "Solid fundamentals.")
        self.assertEqual(body["improvements"], ["Give concrete examples."])
        self.assertEqual(body["mistakes"], ["Confused B-tree with BST."])
        self.assertEqual(body["rubric"]["structure"], 8)
        self.assertEqual(len(body["answers"]), 1)
        self.assertEqual(body["answers"][0]["score"], 6.8)
        self.assertEqual(body["answers"][0]["level"], 3)

        stored = self._load(session_id).overall_feedback
        self.assertIsNotNone(stored)
        self.assertEqual(json.loads(stored), body)

        again, generator = self._post_feedback(session_id)
        self.assertEqual(again.status_code, 200)
        generator.assert_not_called()
        self.assertEqual(again.json(), body)

    def test_feedback_on_in_progress_session_completes_it(self):
        session_id = self._start()["session_id"]
        self._respond(session_id)
        self.assertEqual(self._load(session_id).status, InterviewStatus.IN_PROGRESS)

        response, _ = self._post_feedback(session_id)
        self.assertEqual(response.status_code, 200, response.text)
        interview = self._load(session_id)
        self.assertEqual(interview.status, InterviewStatus.COMPLETED)
        self.assertIsNotNone(interview.ended_at)

    def test_feedback_on_abandoned_session_keeps_it_abandoned(self):
        session_id = self._start()["session_id"]
        self._respond(session_id, follow_up=_follow_up("Stopping.", complete=True, ended_early=True))
        response, _ = self._post_feedback(session_id)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(self._load(session_id).status, InterviewStatus.ABANDONED)

    def test_feedback_without_any_answers_is_409(self):
        session_id = self._start()["session_id"]
        response, generator = self._post_feedback(session_id)
        self.assertEqual(response.status_code, 409)
        generator.assert_not_called()
        self.assertIsNone(self._load(session_id).overall_feedback)

    def test_feedback_for_another_users_session_is_404(self):
        session_id = self._start()["session_id"]
        self._respond(session_id)
        response, generator = self._post_feedback(session_id, headers=self.other_headers)
        self.assertEqual(response.status_code, 404)
        generator.assert_not_called()
        self.assertIsNone(self._load(session_id).overall_feedback)

    def test_feedback_for_unknown_session_is_404(self):
        response, generator = self._post_feedback(999_999)
        self.assertEqual(response.status_code, 404)
        generator.assert_not_called()

    # -- get -------------------------------------------------------------

    def test_get_returns_transcript_and_feedback_to_owner(self):
        session_id = self._start()["session_id"]
        self._respond(session_id, answer="My answer.")

        response = self.client.get(f"/api/interview/{session_id}", headers=self.headers)
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertEqual(body["id"], session_id)
        self.assertEqual(body["target_role"], "Backend Engineer")
        self.assertEqual(body["status"], "in_progress")
        self.assertIsNone(body["feedback"])
        self.assertEqual(
            [(t["speaker"], t["text"]) for t in body["transcript"]],
            [("ai", OPENING), ("user", "My answer."), ("ai", "Good. Next: what is a B-tree?")],
        )

        self._post_feedback(session_id)
        body = self.client.get(f"/api/interview/{session_id}", headers=self.headers).json()
        self.assertEqual(body["feedback"]["rating"], 7)
        self.assertEqual(body["status"], "completed")

    def test_get_another_users_session_is_404(self):
        session_id = self._start()["session_id"]
        response = self.client.get(f"/api/interview/{session_id}", headers=self.other_headers)
        self.assertEqual(response.status_code, 404)

    def test_get_unknown_session_is_404(self):
        response = self.client.get("/api/interview/999999", headers=self.headers)
        self.assertEqual(response.status_code, 404)

    # -- transcribe ------------------------------------------------------

    def _transcribe(self, data: bytes, headers=None):
        with mock.patch(f"{ROUTES}.transcribe_audio", return_value="hello world") as transcriber:
            response = self.client.post(
                "/api/interview/transcribe",
                files={"audio": ("answer.m4a", data, "audio/m4a")},
                headers=self.headers if headers is None else headers,
            )
        return response, transcriber

    def test_transcribe_empty_upload_is_400(self):
        response, transcriber = self._transcribe(b"")
        self.assertEqual(response.status_code, 400)
        transcriber.assert_not_called()

    def test_transcribe_oversized_upload_is_413(self):
        with mock.patch.object(settings, "max_audio_upload_bytes", 16):
            response, transcriber = self._transcribe(b"x" * 17)
            self.assertEqual(response.status_code, 413)
            transcriber.assert_not_called()

            at_limit, transcriber = self._transcribe(b"x" * 16)
            self.assertEqual(at_limit.status_code, 200, at_limit.text)

    def test_transcribe_passes_bytes_to_transcriber_and_returns_text(self):
        audio = b"\x00\x01fake-m4a-bytes"
        response, transcriber = self._transcribe(audio)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json(), {"text": "hello world"})
        transcriber.assert_called_once()
        data, filename, content_type = transcriber.call_args.args
        self.assertEqual(data, audio)
        self.assertEqual(filename, "answer.m4a")
        self.assertEqual(content_type, "audio/m4a")

    # -- auth ------------------------------------------------------------

    def test_every_endpoint_requires_a_token(self):
        session_id = self._start()["session_id"]
        with mock.patch(f"{ROUTES}.generate_first_question") as first, \
                mock.patch(f"{ROUTES}.generate_follow_up") as follow, \
                mock.patch(f"{ROUTES}.generate_feedback") as feedback, \
                mock.patch(f"{ROUTES}.transcribe_audio") as transcriber:
            requests = [
                ("POST /start", lambda h: self.client.post(
                    "/api/interview/start", json={"target_role": "SWE"}, headers=h)),
                ("POST /respond", lambda h: self.client.post(
                    "/api/interview/respond",
                    json={"session_id": session_id, "transcribed_answer": "x"}, headers=h)),
                ("POST /feedback", lambda h: self.client.post(
                    f"/api/interview/{session_id}/feedback", headers=h)),
                ("GET /{id}", lambda h: self.client.get(
                    f"/api/interview/{session_id}", headers=h)),
                ("POST /transcribe", lambda h: self.client.post(
                    "/api/interview/transcribe",
                    files={"audio": ("a.m4a", b"abc", "audio/m4a")}, headers=h)),
            ]
            bad_headers = {
                "no token": {},
                "garbage token": {"Authorization": "Bearer not-a-jwt"},
            }
            for name, send in requests:
                for label, headers in bad_headers.items():
                    with self.subTest(endpoint=name, auth=label):
                        self.assertEqual(send(headers).status_code, 401)
            for generator in (first, follow, feedback, transcriber):
                generator.assert_not_called()


if __name__ == "__main__":
    unittest.main()
