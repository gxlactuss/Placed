import os
import tempfile
import unittest
from datetime import datetime, timezone
from unittest import mock

from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlmodel import Session, create_engine, select

import database.db as db
from app.core.config import Settings, settings
from app.core.rate_limit import reset_rate_limits
from app.main import app
from database.models.user import User


class SignupVerificationCodeTests(unittest.TestCase):

    def setUp(self):
        handle, self.path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        url = f"sqlite:///{self.path}"
        self.engine = create_engine(url, connect_args={"check_same_thread": False})
        self.send_email = mock.MagicMock()
        self.patches = [
            mock.patch.object(db, "engine", self.engine),
            mock.patch.object(db, "DATABASE_URL", url),
            # Pin to the default so a local .env can't change what these tests assert.
            mock.patch.object(settings, "dev_verification_code", ""),
            mock.patch("app.auth.routes.send_verification_email", self.send_email),
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

    def _signup(self, email: str = "alice@example.com", ip: str = "203.0.113.1"):
        with TestClient(app) as client:
            response = client.post(
                "/api/auth/signup",
                json={"email": email, "password": "password123"},
                headers={"Fly-Client-IP": ip},
            )
        self.assertEqual(response.status_code, 201, response.text)
        with Session(self.engine) as session:
            return session.exec(select(User).where(User.email == email)).one()

    def test_default_settings_issue_random_expiring_code_and_send_email(self):
        user = self._signup()

        self.assertRegex(user.verification_code, r"^\d{6}$")
        self.assertIsNotNone(user.verification_code_expires_at)
        now_naive = datetime.now(timezone.utc).replace(tzinfo=None)
        self.assertGreater(user.verification_code_expires_at, now_naive)
        self.send_email.assert_called_once_with("alice@example.com", user.verification_code)

    def test_default_settings_do_not_reuse_a_fixed_code(self):
        codes = {
            self._signup(f"user{i}@example.com", ip=f"203.0.113.{i + 10}").verification_code
            for i in range(3)
        }
        # Three random 6-digit codes colliding entirely is ~1e-12.
        self.assertGreater(len(codes), 1)

    def test_dev_code_is_used_when_set(self):
        with mock.patch.object(settings, "dev_verification_code", "123456"):
            user = self._signup()

        self.assertEqual(user.verification_code, "123456")
        self.assertIsNone(user.verification_code_expires_at)
        self.send_email.assert_not_called()


class DevVerificationCodeValidatorTests(unittest.TestCase):

    def setUp(self):
        # _env_file=None skips .env; also keep real environment variables out.
        env = {k: v for k, v in os.environ.items()
               if k.upper() not in {"DEV_VERIFICATION_CODE", "RESEND_API_KEY"}}
        patch = mock.patch.dict(os.environ, env, clear=True)
        patch.start()
        self.addCleanup(patch.stop)

    def test_default_is_empty(self):
        self.assertEqual(Settings(_env_file=None).dev_verification_code, "")

    def test_dev_code_alone_is_allowed(self):
        built = Settings(_env_file=None, dev_verification_code="123456")
        self.assertEqual(built.dev_verification_code, "123456")

    def test_resend_key_alone_is_allowed(self):
        built = Settings(_env_file=None, resend_api_key="re_test")
        self.assertEqual(built.resend_api_key, "re_test")

    def test_dev_code_with_resend_key_is_rejected(self):
        with self.assertRaises(ValidationError) as ctx:
            Settings(_env_file=None, dev_verification_code="123456", resend_api_key="re_test")
        self.assertIn("DEV_VERIFICATION_CODE must be empty", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
