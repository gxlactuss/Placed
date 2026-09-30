import io
import logging
import os
import tempfile
import unittest
from unittest import mock

from fastapi.testclient import TestClient
from sqlmodel import Session, create_engine

import database.db as db
from app.auth import email_service
from app.auth.jwt import hash_password
from app.core.config import settings
from app.core.logging import KeyValueFormatter, email_fingerprint
from app.core.rate_limit import limiter, reset_rate_limits
from app.main import app
from database.models.user import User


class AuthLoggingTests(unittest.TestCase):

    def setUp(self):
        handle, self.path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        url = f"sqlite:///{self.path}"
        self.engine = create_engine(url, connect_args={"check_same_thread": False})
        self.patches = [
            mock.patch.object(db, "engine", self.engine),
            mock.patch.object(db, "DATABASE_URL", url),
            mock.patch.object(limiter, "enabled", False),
            mock.patch("app.auth.routes.send_verification_email"),
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

    def test_failed_login_logs_email_hash_not_email(self):
        email = "Carol.Private@example.com"
        with TestClient(app) as client:  # startup creates the tables
            with Session(self.engine) as session:
                session.add(User(email=email, hashed_password=hash_password("password123")))
                session.commit()

            with self.assertLogs("app.auth.routes", level="INFO") as logs:
                response = client.post(
                    "/api/auth/login", json={"email": email, "password": "wrong-password"}
                )

        self.assertEqual(response.status_code, 401)
        output = "\n".join(logs.output)
        self.assertIn("login_failed reason=bad_password", output)
        self.assertIn(f"email_hash={email_fingerprint(email)}", output)
        self.assertNotIn(email, output)
        self.assertNotIn(email.lower(), output)
        self.assertNotIn("wrong-password", output)

    def test_signup_success_logs_user_id(self):
        with TestClient(app) as client:
            with self.assertLogs("app.auth.routes", level="INFO") as logs:
                response = client.post(
                    "/api/auth/signup",
                    json={"email": "dave@example.com", "password": "password123"},
                )

        self.assertEqual(response.status_code, 201)
        user_id = response.json()["user"]["id"]
        output = "\n".join(logs.output)
        self.assertIn(f"signup_success user_id={user_id}", output)
        self.assertNotIn("dave@example.com", output)
        self.assertNotIn("password123", output)

    def test_email_send_failure_does_not_log_address(self):
        with (
            mock.patch.object(settings, "resend_api_key", "test-key"),
            mock.patch.object(email_service.httpx, "post", side_effect=RuntimeError("boom")),
            self.assertLogs("app.auth.email_service", level="ERROR") as logs,
        ):
            email_service.send_verification_email("erin@example.com", "987654")

        output = "\n".join(logs.output)
        self.assertIn("verification_email_failed", output)
        self.assertNotIn("erin@example.com", output)
        self.assertNotIn("987654", output)


class FormatterTests(unittest.TestCase):

    def test_record_renders_as_one_key_value_line(self):
        stream = io.StringIO()
        handler = logging.StreamHandler(stream)
        handler.setFormatter(KeyValueFormatter())
        logger = logging.getLogger("tests.formatter")
        logger.addHandler(handler)
        try:
            logger.warning("first line\nsecond line")
        finally:
            logger.removeHandler(handler)

        line = stream.getvalue()
        self.assertEqual(line.count("\n"), 1)
        self.assertRegex(
            line,
            r'^ts=\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z level=WARNING '
            r'logger=tests\.formatter msg="first line\\nsecond line"\n$',
        )


if __name__ == "__main__":
    unittest.main()
