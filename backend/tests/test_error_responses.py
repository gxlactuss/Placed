import os
import tempfile
import unittest
from unittest import mock

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlmodel import Session, create_engine

import database.db as db
from app.auth.jwt import create_access_token, hash_password
from app.core.errors import GENERIC_SERVER_ERROR, register_error_handlers
from app.core.rate_limit import reset_rate_limits
from app.main import app
from database.models.user import User


class ErrorResponseTests(unittest.TestCase):

    def setUp(self):
        handle, self.path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        url = f"sqlite:///{self.path}"
        self.engine = create_engine(url, connect_args={"check_same_thread": False})
        self.patches = [
            mock.patch.object(db, "engine", self.engine),
            mock.patch.object(db, "DATABASE_URL", url),
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

    def _auth_headers(self) -> dict:
        with Session(self.engine) as session:
            user = User(email="alice@example.com", hashed_password=hash_password("password123"))
            session.add(user)
            session.commit()
            session.refresh(user)
            user_id = user.id
        return {"Authorization": f"Bearer {create_access_token(str(user_id))}"}

    def test_short_password_returns_string_detail_and_error_list(self):
        with TestClient(app) as client:
            response = client.post(
                "/api/auth/signup",
                json={"email": "alice@example.com", "password": "pw1xq"},
            )

        self.assertEqual(response.status_code, 422)
        body = response.json()
        self.assertIsInstance(body["detail"], str)
        self.assertEqual(body["detail"], "password: String should have at least 8 characters")
        self.assertIsInstance(body["errors"], list)
        self.assertEqual(body["errors"][0]["loc"], ["body", "password"])
        # The rejected value (a password here) is not echoed back.
        self.assertNotIn("input", body["errors"][0])
        self.assertNotIn("pw1xq", response.text)

    def test_invalid_email_and_missing_body_give_readable_detail(self):
        with TestClient(app) as client:
            bad_email = client.post(
                "/api/auth/signup", json={"email": "not-an-email", "password": "password123"}
            )
            no_body = client.post("/api/auth/signup")

        self.assertEqual(bad_email.status_code, 422)
        self.assertTrue(bad_email.json()["detail"].startswith("email: "))
        self.assertEqual(no_body.status_code, 422)
        self.assertEqual(no_body.json()["detail"], "Request body: Field required")

    def test_unhandled_exception_returns_generic_json_500_and_logs(self):
        throwaway = FastAPI()
        register_error_handlers(throwaway)

        @throwaway.get("/boom")
        def boom():
            raise RuntimeError("database exploded")

        with self.assertLogs("app.errors", level="ERROR") as logs:
            with TestClient(throwaway, raise_server_exceptions=False) as client:
                response = client.get("/boom")

        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.json(), {"detail": GENERIC_SERVER_ERROR})
        self.assertNotIn("database exploded", response.text)
        self.assertIn("GET /boom", logs.output[0])

    def test_http_exception_keeps_its_own_detail(self):
        with TestClient(app) as client:
            response = client.get("/api/interview/999999", headers=self._auth_headers())

        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json(), {"detail": "Interview session not found"})


if __name__ == "__main__":
    unittest.main()
