import os
import sqlite3
import tempfile
import unittest
from unittest import mock

from fastapi.testclient import TestClient
from sqlalchemy import event
from sqlmodel import Session, create_engine

import database.db as db
from database.models.user import User
from app.ai import resume_checks
from app.ai.llm_service import FactorScore, ResumeReview
from app.ai.redaction import redact_contact_details
from app.auth.jwt import create_access_token
from app.main import app

EMAILS = ("first.last+jobs@mail.example.co.in", "a_b-c.d@uni.edu")
PHONES = (
    "+91 9876543210",
    "+91-9876543210",
    "9876543210",
    "+44 7911123456",
    "555-123-4567",
    "+91 98765 43210",
    "+1 (555) 123-4567",
)

# Keep these two lists identical to the phoneNumbersAreRedacted /
# ordinaryNumbersAreNotRedacted arguments in
# frontend/PlacementPrepTests/ResumeParserTests.swift: both sides share one
# phone regex (app/ai/redaction.py <-> Services/ResumeParser.swift).
PHONE_SAMPLES = (
    "9876543210",
    "+91 9876543210",
    "+91-9876543210",
    "+91 98765 43210",
    "98765 43210",
    "98765-43210",
    "+919876543210",
    "919876543210",
    "098765 43210",
    "0091 98765 43210",
    "+44 7911123456",
    "+1 5551234567",
    "555-123-4567",
    "555.123.4567",
    "555 123 4567",
    "(555) 123-4567",
    "+1 (555) 123-4567",
)
NOT_PHONE_SAMPLES = (
    "2019",
    "2019-2023",
    "2019 - 2023",
    "Jan 2019 – May 2023",
    "CGPA 9.12/10",
    "99.5% uptime",
    "v1.2.3",
    "Mumbai 400001",
    "12/05/2023",
    "2023-05-12",
    "reduced latency by 800ms to 120ms",
    "1,50,000 users",
    "1,200,000 requests/day",
    "Top 1% of 150000 candidates",
    "Roll no. 190123456",
)

RESUME = (
    "Jane Doe\n"
    f"{EMAILS[0]} | {PHONES[0]} | {PHONES[4]} | {PHONES[5]} | {PHONES[6]}\n"
    "EDUCATION\n"
    "B.Tech Computer Science, 2019-2023, CGPA 9.1\n"
    "EXPERIENCE\n"
    f"- Built a payments service handling 99.5% uptime; contact {EMAILS[1]} or {PHONES[2]}\n"
    "- Reduced latency by 40% across 3 regions\n"
    "PROJECTS\n"
    "- Placed: interview prep app in SwiftUI and FastAPI\n"
)


def _assert_clean(test, text):
    for secret in EMAILS:
        test.assertNotIn(secret, text)
    test.assertNotIn("@", text)
    for secret in ("9876543210", "7911123456", "555-123-4567", "98765 43210", "(555) 123-4567"):
        test.assertNotIn(secret, text)


class RedactorTests(unittest.TestCase):

    def test_redacts_emails_with_plus_and_dots(self):
        for email in EMAILS:
            with self.subTest(email=email):
                self.assertEqual(redact_contact_details(f"mail {email} now"), "mail [redacted] now")

    def test_redacts_indian_numbers_including_country_code(self):
        for phone in ("+91 9876543210", "+91-9876543210", "9876543210"):
            with self.subTest(phone=phone):
                self.assertEqual(redact_contact_details(f"call {phone}."), "call [redacted].")

    def test_redacts_international_numbers(self):
        cases = {
            "+44 7911123456": "[redacted]",
            "+1 5551234567": "[redacted]",
            "555-123-4567": "[redacted]",
            "555.123.4567": "[redacted]",
            "555 123 4567": "[redacted]",
        }
        for phone, expected in cases.items():
            with self.subTest(phone=phone):
                self.assertEqual(redact_contact_details(phone), expected)

    def test_redacts_shared_phone_samples(self):
        # Same wrapper as the Swift test, so both sides check identical input.
        for phone in PHONE_SAMPLES:
            with self.subTest(phone=phone):
                output = redact_contact_details(f"Phone: {phone} (mobile)")
                self.assertEqual(output, "Phone: [redacted] (mobile)")
                self.assertFalse(any(ch.isdigit() for ch in output), output)

    def test_leaves_shared_non_phone_samples_alone(self):
        for text in NOT_PHONE_SAMPLES:
            with self.subTest(text=text):
                self.assertEqual(redact_contact_details(text), text)

    def test_leaves_ordinary_numbers_alone(self):
        for text in (
            "2019-2023",
            "2019 - 2023",
            "Jan 2019 – May 2023",
            "99.5% uptime",
            "CGPA 9.12/10",
            "Top 1% of 150000 candidates",
            "Roll no. 190123456",
            "v1.2.3",
            "https://github.com/jane/placed",
        ):
            with self.subTest(text=text):
                self.assertEqual(redact_contact_details(text), text)

    def test_idempotent_and_keeps_existing_placeholders(self):
        once = redact_contact_details(RESUME)
        self.assertEqual(redact_contact_details(once), once)
        self.assertEqual(redact_contact_details("[redacted] | [redacted]"), "[redacted] | [redacted]")


class ResumeEndpointPrivacyTests(unittest.TestCase):

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
        # The token must belong to a real user (deleted-user tokens get 401).
        db.init_db()
        with Session(self.engine) as session:
            user = User(email="jane@example.com", hashed_password="x")
            session.add(user)
            session.commit()
            session.refresh(user)
            user_id = user.id
        self.headers = {"Authorization": f"Bearer {create_access_token(str(user_id))}"}

    def tearDown(self):
        for patch in self.patches:
            patch.stop()
        self.engine.dispose()
        os.remove(self.path)

    def _row_counts(self):
        with sqlite3.connect(self.path) as connection:
            tables = [
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
                )
            ]
            return {t: connection.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0] for t in tables}

    def _post_without_writes(self, client, url, body):
        writes = []

        def record(conn, cursor, statement, parameters, context, executemany):
            if statement.lstrip().split(None, 1)[0].upper() in {"INSERT", "UPDATE", "DELETE", "REPLACE"}:
                writes.append(statement)

        before = self._row_counts()
        self.assertTrue(before, "init_db should have created the tables")
        event.listen(self.engine, "before_cursor_execute", record)
        try:
            response = client.post(url, json=body, headers=self.headers)
        finally:
            event.remove(self.engine, "before_cursor_execute", record)
        self.assertEqual(writes, [])
        self.assertEqual(self._row_counts(), before)
        return response

    def test_review_strips_contact_details_before_the_llm_and_writes_nothing(self):
        review = ResumeReview(
            overall=70,
            factors=[FactorScore("impact", 30, 7, "ok")],
            strengths=["Clear projects"],
            improvements=[],
            rewrites=[],
        )
        body = {
            "target_role": "Backend Engineer",
            "resume_text": RESUME,
            "device": {
                "has_email": True,
                "has_phone": True,
                "has_links": False,
                "page_count": 1,
                "has_text_layer": True,
            },
        }
        with TestClient(app) as client, mock.patch(
            "app.ai.resume_routes.generate_resume_review", return_value=review
        ) as generate, mock.patch(
            "app.ai.resume_routes.analyse", wraps=resume_checks.analyse
        ) as analyse:
            response = self._post_without_writes(client, "/api/resume/review", body)

        self.assertEqual(response.status_code, 200, response.text)
        sent = generate.call_args.args[1]
        _assert_clean(self, sent)
        self.assertIn("[redacted]", sent)
        self.assertIn("2019-2023", sent)
        self.assertIn("99.5%", sent)
        _assert_clean(self, analyse.call_args.args[0])

    def test_resume_summary_strips_contact_details_before_the_llm_and_writes_nothing(self):
        body = {"target_role": "Backend Engineer", "projects_text": RESUME}
        with TestClient(app) as client, mock.patch(
            "app.ai.routes.summarize_projects", return_value=("- Placed: prep app", False)
        ) as summarize:
            response = self._post_without_writes(client, "/api/interview/resume-summary", body)

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["summary"], "- Placed: prep app")
        sent = summarize.call_args.args[1]
        _assert_clean(self, sent)
        self.assertIn("[redacted]", sent)
        self.assertIn("2019-2023", sent)


if __name__ == "__main__":
    unittest.main()
