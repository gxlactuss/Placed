import os
import tempfile
import unittest
from unittest import mock

from fastapi.testclient import TestClient
from sqlmodel import Session, create_engine

import database.db as db
from app.auth.jwt import create_access_token, hash_password
from app.core.config import settings
from app.core.rate_limit import limiter, reset_rate_limits
from app.main import app
from database.models.user import User


class RateLimitTests(unittest.TestCase):

    def setUp(self):
        handle, self.path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        url = f"sqlite:///{self.path}"
        self.engine = create_engine(url, connect_args={"check_same_thread": False})
        self.patches = [
            mock.patch.object(db, "engine", self.engine),
            mock.patch.object(db, "DATABASE_URL", url),
            # Pin the limits so a local .env can't change what these tests assert.
            mock.patch.object(limiter, "enabled", True),
            mock.patch.object(settings, "rate_limit_login", "5/minute;30/hour"),
            mock.patch.object(settings, "rate_limit_verify", "5/minute;20/hour"),
            mock.patch.object(settings, "rate_limit_resend_verification", "1/minute;5/hour"),
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

    def _make_user(self, email: str) -> dict:
        with Session(self.engine) as session:
            user = User(
                email=email,
                hashed_password=hash_password("password123"),
                verification_code="654321",
            )
            session.add(user)
            session.commit()
            session.refresh(user)
            user_id = user.id
        return {"Authorization": f"Bearer {create_access_token(str(user_id))}"}

    def _login(self, client, ip: str, **extra_headers):
        return client.post(
            "/api/auth/login",
            json={"email": "nobody@example.com", "password": "wrong-password"},
            headers={"Fly-Client-IP": ip, **extra_headers},
        )

    def test_sixth_login_in_a_minute_is_rejected_with_detail_and_retry_after(self):
        with TestClient(app) as client:
            for _ in range(5):
                self.assertEqual(self._login(client, "203.0.113.1").status_code, 401)

            response = self._login(client, "203.0.113.1")

        self.assertEqual(response.status_code, 429)
        detail = response.json()["detail"]
        self.assertIsInstance(detail, str)
        self.assertIn("Too many sign-in attempts", detail)
        retry_after = int(response.headers["Retry-After"])
        self.assertGreaterEqual(retry_after, 1)
        self.assertLessEqual(retry_after, 60)

    def test_fly_client_ip_distinguishes_clients(self):
        with TestClient(app) as client:
            for _ in range(5):
                self._login(client, "203.0.113.1")
            self.assertEqual(self._login(client, "203.0.113.1").status_code, 429)

            # A different client gets its own bucket.
            self.assertEqual(self._login(client, "198.51.100.7").status_code, 401)

            # X-Forwarded-For is not trusted, so it can't be used to dodge the limit.
            spoofed = self._login(client, "203.0.113.1", **{"X-Forwarded-For": "192.0.2.99"})
            self.assertEqual(spoofed.status_code, 429)

    def test_verify_is_limited_per_user(self):
        same_ip = {"Fly-Client-IP": "203.0.113.1"}

        with TestClient(app) as client:
            alice = self._make_user("alice@example.com")
            bob = self._make_user("bob@example.com")

            def verify(headers):
                return client.post(
                    "/api/auth/verify", json={"code": "000000"}, headers={**headers, **same_ip}
                )

            for _ in range(5):
                self.assertEqual(verify(alice).status_code, 400)
            blocked = verify(alice)
            self.assertEqual(blocked.status_code, 429)
            self.assertIn("Too many verification attempts", blocked.json()["detail"])
            self.assertIn("Retry-After", blocked.headers)

            # Bob shares Alice's IP but not her bucket.
            self.assertEqual(verify(bob).status_code, 400)

    def test_resend_verification_is_limited_per_user(self):
        with TestClient(app) as client:
            alice = self._make_user("alice@example.com")
            bob = self._make_user("bob@example.com")

            self.assertEqual(
                client.post("/api/auth/resend-verification", headers=alice).status_code, 204
            )
            second = client.post("/api/auth/resend-verification", headers=alice)
            self.assertEqual(second.status_code, 429)
            self.assertIn("A code was sent recently", second.json()["detail"])
            self.assertEqual(
                client.post("/api/auth/resend-verification", headers=bob).status_code, 204
            )

    def test_oauth_limit_redirects_back_to_the_app(self):
        with mock.patch.object(settings, "rate_limit_oauth", "1/minute"):
            with TestClient(app, follow_redirects=False) as client:
                client.get("/api/auth/oauth/google/login")
                limited = client.get("/api/auth/oauth/google/login")

        self.assertEqual(limited.status_code, 302)
        self.assertEqual(
            limited.headers["location"],
            f"{settings.app_redirect_scheme}://oauth?error=rate_limited",
        )
        self.assertIn("retry-after", limited.headers)


if __name__ == "__main__":
    unittest.main()
