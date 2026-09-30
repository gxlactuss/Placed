"""Contract tests for the auth router (signup, login, verify, /me) and OAuth.

Code generation, rate limits, logging, account deletion and error shapes have
their own test files; this one covers the request/response contract. The
limiter is disabled here so the many signups/logins below don't trip it.
"""

import os
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock
from urllib.parse import parse_qs, urlparse

from fastapi.testclient import TestClient
from sqlmodel import Session, create_engine, select

import database.db as db
from app.auth import oauth_service
from app.auth.jwt import create_access_token, decode_access_token, hash_password
from app.auth.schemas import UserUpdate
from app.core.config import settings
from app.core.rate_limit import limiter, reset_rate_limits
from app.main import app
from database.models.user import User

PASSWORD = "password123"


def _bearer(user_id) -> dict:
    return {"Authorization": f"Bearer {create_access_token(str(user_id))}"}


class AuthRouteTestCase(unittest.TestCase):

    def setUp(self):
        handle, self.path = tempfile.mkstemp(suffix=".db")
        os.close(handle)
        url = f"sqlite:///{self.path}"
        self.engine = create_engine(url, connect_args={"check_same_thread": False})
        self.send_email = mock.MagicMock()
        self.patches = [
            mock.patch.object(db, "engine", self.engine),
            mock.patch.object(db, "DATABASE_URL", url),
            mock.patch.object(limiter, "enabled", False),
            # Pin settings so a local .env can't change what these tests assert.
            mock.patch.object(settings, "dev_verification_code", ""),
            mock.patch.object(settings, "app_redirect_scheme", "placementprep"),
            mock.patch.object(settings, "google_client_id", ""),
            mock.patch.object(settings, "google_client_secret", ""),
            mock.patch.object(settings, "github_client_id", ""),
            mock.patch.object(settings, "github_client_secret", ""),
            mock.patch("app.auth.routes.send_verification_email", self.send_email),
        ]
        for patch in self.patches:
            patch.start()
        reset_rate_limits()
        self.client_cm = TestClient(app)
        self.client = self.client_cm.__enter__()  # runs lifespan: creates tables

    def tearDown(self):
        self.client_cm.__exit__(None, None, None)
        reset_rate_limits()
        for patch in self.patches:
            patch.stop()
        self.engine.dispose()
        os.remove(self.path)

    # helpers

    def _signup(self, email="alice@example.com", password=PASSWORD, **extra):
        return self.client.post(
            "/api/auth/signup", json={"email": email, "password": password, **extra}
        )

    def _make_user(self, email="alice@example.com", **fields) -> int:
        with Session(self.engine) as session:
            user = User(email=email, hashed_password=hash_password(PASSWORD), **fields)
            session.add(user)
            session.commit()
            session.refresh(user)
            return user.id

    def _get_user(self, user_id: int) -> User | None:
        with Session(self.engine) as session:
            return session.get(User, user_id)

    def _users(self) -> list[User]:
        with Session(self.engine) as session:
            return list(session.exec(select(User)).all())


class SignupTests(AuthRouteTestCase):

    def test_signup_returns_201_token_and_user(self):
        response = self._signup(full_name="Alice", target_role="iOS Engineer")

        self.assertEqual(response.status_code, 201, response.text)
        body = response.json()
        self.assertEqual(body["token_type"], "bearer")
        self.assertTrue(body["access_token"])
        user = body["user"]
        self.assertEqual(user["email"], "alice@example.com")
        self.assertEqual(user["full_name"], "Alice")
        self.assertEqual(user["target_role"], "iOS Engineer")
        self.assertFalse(user["is_verified"])
        self.assertFalse(user["onboarded"])
        self.assertNotIn("hashed_password", user)
        self.assertNotIn("verification_code", user)
        self.assertEqual(decode_access_token(body["access_token"]), str(user["id"]))

        stored = self._get_user(user["id"])
        self.assertNotEqual(stored.hashed_password, PASSWORD)

    def test_signup_token_works_on_me(self):
        body = self._signup().json()

        me = self.client.get(
            "/api/auth/me", headers={"Authorization": f"Bearer {body['access_token']}"}
        )

        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.json(), body["user"])

    def test_duplicate_email_is_rejected(self):
        self.assertEqual(self._signup().status_code, 201)

        again = self._signup(password="another-password")

        self.assertEqual(again.status_code, 400)
        self.assertEqual(again.json()["detail"], "Email already registered")
        self.assertEqual(len(self._users()), 1)
        self.send_email.assert_called_once()  # only for the first signup

    def test_signup_stores_the_normalised_email(self):
        response = self._signup("  Bob@Example.COM ")

        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()["user"]["email"], "bob@example.com")
        self.assertEqual([u.email for u in self._users()], ["bob@example.com"])

    def test_case_variant_of_an_existing_email_is_rejected(self):
        self.assertEqual(self._signup("alice@example.com").status_code, 201)

        again = self._signup("ALICE@Example.com")

        self.assertEqual(again.status_code, 400)
        self.assertEqual(again.json()["detail"], "Email already registered")
        self.assertEqual(len(self._users()), 1)

    def test_case_variant_of_a_legacy_mixed_case_row_is_rejected(self):
        # Rows written before normalisation may hold mixed case.
        self._make_user("Legacy@example.com")

        again = self._signup("legacy@example.com")

        self.assertEqual(again.status_code, 400)
        self.assertEqual(len(self._users()), 1)


class LoginTests(AuthRouteTestCase):

    def setUp(self):
        super().setUp()
        self.user_id = self._make_user("alice@example.com")

    def _login(self, email, password):
        return self.client.post("/api/auth/login", json={"email": email, "password": password})

    def test_login_success_returns_token_for_the_user(self):
        response = self._login("alice@example.com", PASSWORD)

        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertEqual(body["token_type"], "bearer")
        self.assertEqual(body["user"]["id"], self.user_id)
        self.assertEqual(body["user"]["email"], "alice@example.com")
        self.assertEqual(decode_access_token(body["access_token"]), str(self.user_id))
        me = self.client.get(
            "/api/auth/me", headers={"Authorization": f"Bearer {body['access_token']}"}
        )
        self.assertEqual(me.status_code, 200)

    def test_wrong_password_is_401(self):
        response = self._login("alice@example.com", "wrong-password")

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"], "Incorrect email or password")
        self.assertNotIn("access_token", response.json())

    def test_unknown_email_is_indistinguishable_from_wrong_password(self):
        wrong_password = self._login("alice@example.com", "wrong-password")
        unknown_email = self._login("nobody@example.com", PASSWORD)

        self.assertEqual(unknown_email.status_code, 401)
        self.assertEqual(unknown_email.status_code, wrong_password.status_code)
        self.assertEqual(unknown_email.json(), wrong_password.json())

    # iOS keyboards capitalise the first letter by default, so the address a
    # user types can differ in case between signup and login.
    def test_login_with_the_exact_email_used_at_signup_succeeds(self):
        self.assertEqual(self._signup("Bob@Example.COM").status_code, 201)

        response = self._login("Bob@Example.COM", PASSWORD)

        self.assertEqual(response.status_code, 200, response.text)

    def test_login_email_is_case_and_whitespace_insensitive(self):
        for email in ("Alice@Example.com", "ALICE@EXAMPLE.COM", " alice@example.com "):
            response = self._login(email, PASSWORD)
            self.assertEqual(response.status_code, 200, (email, response.text))
            self.assertEqual(response.json()["user"]["id"], self.user_id)

    def test_login_matches_a_legacy_mixed_case_row(self):
        legacy_id = self._make_user("Bob@example.com")

        response = self._login("bob@example.com", PASSWORD)

        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["user"]["id"], legacy_id)

    def test_case_variant_with_wrong_password_is_the_usual_401(self):
        wrong_password = self._login("ALICE@example.com", "wrong-password")
        unknown_email = self._login("NOBODY@example.com", PASSWORD)

        self.assertEqual(wrong_password.status_code, 401)
        self.assertEqual(unknown_email.json(), wrong_password.json())


class VerifyTests(AuthRouteTestCase):

    def _verify(self, user_id, code):
        return self.client.post("/api/auth/verify", json={"code": code}, headers=_bearer(user_id))

    def test_correct_code_verifies_and_clears_the_code(self):
        user_id = self._make_user(
            verification_code="123456",
            verification_code_expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
        )

        response = self._verify(user_id, "123456")

        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(response.json()["is_verified"])
        stored = self._get_user(user_id)
        self.assertTrue(stored.is_verified)
        self.assertIsNone(stored.verification_code)
        self.assertIsNone(stored.verification_code_expires_at)

    def test_signup_code_verifies_end_to_end(self):
        body = self._signup().json()
        code = self.send_email.call_args.args[1]

        response = self.client.post(
            "/api/auth/verify",
            json={"code": code},
            headers={"Authorization": f"Bearer {body['access_token']}"},
        )

        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(response.json()["is_verified"])

    def test_wrong_code_is_400_and_leaves_user_unverified(self):
        user_id = self._make_user(
            verification_code="123456",
            verification_code_expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
        )

        response = self._verify(user_id, "000000")

        self.assertEqual(response.status_code, 400)
        self.assertIn("isn't right", response.json()["detail"])
        stored = self._get_user(user_id)
        self.assertFalse(stored.is_verified)
        self.assertEqual(stored.verification_code, "123456")

    def test_user_without_a_code_cannot_verify_with_empty_code(self):
        user_id = self._make_user(verification_code=None)

        response = self._verify(user_id, "")

        self.assertEqual(response.status_code, 400)
        self.assertFalse(self._get_user(user_id).is_verified)

    def test_expired_code_is_400_expired(self):
        user_id = self._make_user(
            verification_code="123456",
            verification_code_expires_at=datetime.now(timezone.utc) - timedelta(minutes=1),
        )

        response = self._verify(user_id, "123456")

        self.assertEqual(response.status_code, 400)
        self.assertIn("expired", response.json()["detail"])
        self.assertFalse(self._get_user(user_id).is_verified)

    def test_already_verified_user_is_a_200_no_op(self):
        user_id = self._make_user(is_verified=True, verification_code=None)

        response = self._verify(user_id, "anything")

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["is_verified"])
        self.assertTrue(self._get_user(user_id).is_verified)

    def test_verify_requires_auth(self):
        response = self.client.post("/api/auth/verify", json={"code": "123456"})

        self.assertEqual(response.status_code, 401)


class ResendVerificationTests(AuthRouteTestCase):

    def test_unverified_user_gets_a_new_code(self):
        user_id = self._make_user(verification_code="111111")

        response = self.client.post("/api/auth/resend-verification", headers=_bearer(user_id))

        self.assertEqual(response.status_code, 204)
        self.assertEqual(response.content, b"")
        stored = self._get_user(user_id)
        self.assertRegex(stored.verification_code, r"^\d{6}$")
        self.assertIsNotNone(stored.verification_code_expires_at)
        self.send_email.assert_called_once_with("alice@example.com", stored.verification_code)

    def test_verified_user_is_a_204_and_nothing_is_sent(self):
        user_id = self._make_user(is_verified=True, verification_code=None)

        response = self.client.post("/api/auth/resend-verification", headers=_bearer(user_id))

        self.assertEqual(response.status_code, 204)
        self.send_email.assert_not_called()
        self.assertIsNone(self._get_user(user_id).verification_code)

    def test_resend_requires_auth(self):
        response = self.client.post("/api/auth/resend-verification")

        self.assertEqual(response.status_code, 401)
        self.send_email.assert_not_called()


class MeTests(AuthRouteTestCase):

    def setUp(self):
        super().setUp()
        self.user_id = self._make_user(
            full_name="Alice", target_role="iOS Engineer", target_company="Apple"
        )
        self.headers = _bearer(self.user_id)

    def test_get_me_returns_the_user(self):
        response = self.client.get("/api/auth/me", headers=self.headers)

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["id"], self.user_id)
        self.assertEqual(body["email"], "alice@example.com")
        self.assertEqual(body["full_name"], "Alice")
        self.assertEqual(body["target_role"], "iOS Engineer")
        self.assertEqual(body["target_company"], "Apple")
        self.assertEqual(
            set(body),
            {"id", "email", "full_name", "target_role", "target_company",
             "is_verified", "onboarded", "created_at"},
        )

    def test_patch_updates_only_provided_fields(self):
        response = self.client.patch(
            "/api/auth/me", json={"onboarded": True}, headers=self.headers
        )

        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertTrue(body["onboarded"])
        self.assertEqual(body["full_name"], "Alice")
        self.assertEqual(body["target_role"], "iOS Engineer")
        self.assertEqual(body["target_company"], "Apple")

        response = self.client.patch(
            "/api/auth/me", json={"full_name": "Alice B"}, headers=self.headers
        )
        stored = self._get_user(self.user_id)
        self.assertEqual(stored.full_name, "Alice B")
        self.assertTrue(stored.onboarded)
        self.assertEqual(stored.target_role, "iOS Engineer")
        self.assertEqual(stored.target_company, "Apple")

    def test_patch_explicit_null_clears_an_optional_field(self):
        response = self.client.patch(
            "/api/auth/me", json={"target_company": None}, headers=self.headers
        )

        self.assertEqual(response.status_code, 200, response.text)
        stored = self._get_user(self.user_id)
        self.assertIsNone(stored.target_company)
        self.assertEqual(stored.full_name, "Alice")

    def test_patch_ignores_fields_outside_the_schema(self):
        response = self.client.patch(
            "/api/auth/me",
            json={"email": "mallory@example.com", "is_verified": True, "full_name": "A"},
            headers=self.headers,
        )

        self.assertEqual(response.status_code, 200, response.text)
        stored = self._get_user(self.user_id)
        self.assertEqual(stored.email, "alice@example.com")
        self.assertFalse(stored.is_verified)
        self.assertEqual(stored.full_name, "A")

    # users.onboarded is NOT NULL; an explicit null used to reach the database
    # and fail with a 500 (IntegrityError). It must be rejected up front.
    def test_patch_null_onboarded_is_a_422(self):
        with TestClient(app, raise_server_exceptions=False) as client, \
                self.assertNoLogs("app.errors", "ERROR"):
            response = client.patch(
                "/api/auth/me", json={"onboarded": None}, headers=self.headers
            )

        self.assertEqual(response.status_code, 422, response.text)
        self.assertFalse(self._get_user(self.user_id).onboarded)

    def test_null_is_rejected_exactly_for_fields_backed_by_not_null_columns(self):
        # Guards future UserUpdate fields: each must agree with its column.
        columns = User.__table__.c
        for field in UserUpdate.model_fields:
            with self.subTest(field=field):
                response = self.client.patch(
                    "/api/auth/me", json={field: None}, headers=self.headers
                )
                if columns[field].nullable:
                    self.assertEqual(response.status_code, 200, response.text)
                    self.assertIsNone(getattr(self._get_user(self.user_id), field))
                else:
                    self.assertEqual(response.status_code, 422, response.text)
                    self.assertIsNotNone(getattr(self._get_user(self.user_id), field))

    def _assert_401(self, headers):
        for method in ("get", "patch"):
            kwargs = {"json": {"full_name": "X"}} if method == "patch" else {}
            response = getattr(self.client, method)("/api/auth/me", headers=headers, **kwargs)
            self.assertEqual(response.status_code, 401, (method, headers, response.text))
            self.assertEqual(response.headers.get("www-authenticate"), "Bearer")
        self.assertEqual(self._get_user(self.user_id).full_name, "Alice")

    def test_missing_token_is_401(self):
        self._assert_401({})

    def test_garbage_token_is_401(self):
        self._assert_401({"Authorization": "Bearer not-a-token"})

    def test_token_signed_with_another_secret_is_401(self):
        import jwt

        forged = jwt.encode(
            {"sub": str(self.user_id), "exp": datetime.now(timezone.utc) + timedelta(hours=1)},
            "some-other-secret-that-is-long-enough-0123456789",
            algorithm=settings.jwt_algorithm,
        )
        self._assert_401({"Authorization": f"Bearer {forged}"})

    def test_expired_token_is_401(self):
        token = create_access_token(str(self.user_id), expires_delta=timedelta(seconds=-1))
        self._assert_401({"Authorization": f"Bearer {token}"})

    def test_token_for_nonexistent_user_is_401(self):
        self._assert_401(_bearer(self.user_id + 999))

    def test_token_with_non_integer_subject_is_401(self):
        self._assert_401(_bearer("not-an-id"))


class OAuthTests(AuthRouteTestCase):

    def _app_redirect(self, response) -> dict:
        """Assert a 302 back to the app and return its query params."""
        self.assertEqual(response.status_code, 302, response.text)
        location = urlparse(response.headers["location"])
        self.assertEqual((location.scheme, location.netloc), ("placementprep", "oauth"))
        return {k: v[0] for k, v in parse_qs(location.query).items()}

    def _get(self, path, **params):
        with self.assertLogs("app.auth.oauth_routes", "INFO"):
            return self.client.get(path, params=params, follow_redirects=False)

    def test_login_unknown_provider_redirects_with_error(self):
        params = self._app_redirect(self._get("/api/auth/oauth/myspace/login"))

        self.assertEqual(params, {"error": "unknown_provider"})

    def test_login_unconfigured_provider_redirects_with_error(self):
        params = self._app_redirect(self._get("/api/auth/oauth/google/login"))

        self.assertEqual(params, {"error": "provider_not_configured"})

    def test_login_configured_provider_redirects_to_provider_with_valid_state(self):
        with mock.patch.object(settings, "github_client_id", "gh-id"), \
                mock.patch.object(settings, "github_client_secret", "gh-secret"):
            response = self.client.get("/api/auth/oauth/github/login", follow_redirects=False)

        self.assertEqual(response.status_code, 302)
        location = urlparse(response.headers["location"])
        self.assertEqual(location.netloc, "github.com")
        query = {k: v[0] for k, v in parse_qs(location.query).items()}
        self.assertEqual(query["client_id"], "gh-id")
        self.assertTrue(query["redirect_uri"].endswith("/api/auth/oauth/github/callback"))
        self.assertNotIn("gh-secret", response.headers["location"])
        self.assertTrue(oauth_service.verify_state("github", query["state"]))
        self.assertFalse(oauth_service.verify_state("google", query["state"]))

    def test_callback_with_provider_error_redirects_with_that_error(self):
        params = self._app_redirect(
            self._get("/api/auth/oauth/google/callback", error="access_denied")
        )

        self.assertEqual(params, {"error": "access_denied"})
        self.assertEqual(self._users(), [])

    def test_callback_for_unconfigured_provider_redirects_with_error(self):
        params = self._app_redirect(
            self._get("/api/auth/oauth/google/callback", code="c", state="s")
        )

        self.assertEqual(params, {"error": "provider_not_configured"})

    def test_callback_with_bad_or_missing_state_redirects_with_error(self):
        complete = mock.MagicMock()
        with mock.patch.object(settings, "google_client_id", "g-id"), \
                mock.patch.object(settings, "google_client_secret", "g-secret"), \
                mock.patch.object(oauth_service, "complete_login", complete):
            bad = self._get("/api/auth/oauth/google/callback", code="c", state="garbage")
            missing = self._get("/api/auth/oauth/google/callback", code="c")
            # A state minted for another provider must not be accepted.
            other = self._get(
                "/api/auth/oauth/google/callback",
                code="c",
                state=oauth_service.make_state("github"),
            )

        for response in (bad, missing, other):
            self.assertEqual(self._app_redirect(response), {"error": "invalid_state"})
        complete.assert_not_called()
        self.assertEqual(self._users(), [])

    def _oauth_success_patches(self, email="oauth@example.com", name="OAuth User"):
        return [
            mock.patch.object(oauth_service, "is_configured", return_value=True),
            mock.patch.object(oauth_service, "verify_state", return_value=True),
            mock.patch.object(oauth_service, "complete_login", return_value=(email, name)),
        ]

    def _successful_callback(self, **kwargs):
        patches = self._oauth_success_patches(**kwargs)
        for patch in patches:
            patch.start()
        try:
            return self._get("/api/auth/oauth/google/callback", code="abc", state="xyz")
        finally:
            for patch in patches:
                patch.stop()

    def test_callback_success_creates_verified_user_and_redirects_with_token(self):
        params = self._app_redirect(self._successful_callback())

        self.assertEqual(set(params), {"token"})
        users = self._users()
        self.assertEqual(len(users), 1)
        user = users[0]
        self.assertEqual(user.email, "oauth@example.com")
        self.assertEqual(user.full_name, "OAuth User")
        self.assertTrue(user.is_verified)
        self.assertFalse(user.onboarded)
        self.assertTrue(user.hashed_password)
        self.assertEqual(decode_access_token(params["token"]), str(user.id))

        me = self.client.get(
            "/api/auth/me", headers={"Authorization": f"Bearer {params['token']}"}
        )
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.json()["email"], "oauth@example.com")
        self.send_email.assert_not_called()

    def test_second_callback_for_same_email_reuses_the_user(self):
        first = self._app_redirect(self._successful_callback())
        second = self._app_redirect(self._successful_callback(name="Different Name"))

        users = self._users()
        self.assertEqual(len(users), 1)
        self.assertEqual(users[0].full_name, "OAuth User")
        self.assertEqual(decode_access_token(first["token"]), str(users[0].id))
        self.assertEqual(decode_access_token(second["token"]), str(users[0].id))

    def test_callback_for_existing_password_user_signs_into_that_account(self):
        user_id = self._make_user("oauth@example.com", is_verified=True)

        params = self._app_redirect(self._successful_callback())

        self.assertEqual(len(self._users()), 1)
        self.assertEqual(decode_access_token(params["token"]), str(user_id))
        # The existing password still works; OAuth must not overwrite it.
        login = self.client.post(
            "/api/auth/login", json={"email": "oauth@example.com", "password": PASSWORD}
        )
        self.assertEqual(login.status_code, 200)

    def test_callback_claims_an_unverified_password_account(self):
        # Pre-hijacking: someone signed up with this address but never
        # verified it. The OAuth user has proven ownership, so the account
        # becomes theirs and the unproven password stops working.
        user_id = self._make_user(
            "oauth@example.com",
            verification_code="123456",
            verification_code_expires_at=datetime.now(timezone.utc) + timedelta(minutes=10),
        )
        old_hash = self._get_user(user_id).hashed_password

        patches = self._oauth_success_patches()
        for patch in patches:
            patch.start()
        try:
            with self.assertLogs("app.auth.oauth_routes", "INFO") as logs:
                response = self.client.get(
                    "/api/auth/oauth/google/callback",
                    params={"code": "abc", "state": "xyz"},
                    follow_redirects=False,
                )
        finally:
            for patch in patches:
                patch.stop()
        params = self._app_redirect(response)

        self.assertEqual(len(self._users()), 1)
        self.assertEqual(decode_access_token(params["token"]), str(user_id))
        stored = self._get_user(user_id)
        self.assertTrue(stored.is_verified)
        self.assertIsNone(stored.verification_code)
        self.assertIsNone(stored.verification_code_expires_at)
        self.assertNotEqual(stored.hashed_password, old_hash)
        login = self.client.post(
            "/api/auth/login", json={"email": "oauth@example.com", "password": PASSWORD}
        )
        self.assertEqual(login.status_code, 401)
        claim = [m for m in logs.output if "oauth_claimed_unverified_account" in m]
        self.assertEqual(len(claim), 1)
        self.assertIn(f"user_id={user_id}", claim[0])
        self.assertNotIn("oauth@example.com", "\n".join(logs.output))

    def test_callback_email_is_normalised_and_matches_case_insensitively(self):
        user_id = self._make_user("Mixed@example.com", is_verified=True)

        params = self._app_redirect(self._successful_callback(email=" MIXED@Example.COM "))

        self.assertEqual(len(self._users()), 1)
        self.assertEqual(decode_access_token(params["token"]), str(user_id))

    def test_callback_stores_a_new_users_email_normalised(self):
        self._app_redirect(self._successful_callback(email="New.User@Example.COM"))

        self.assertEqual([u.email for u in self._users()], ["new.user@example.com"])

    def test_provider_failure_redirects_with_error_and_creates_nothing(self):
        with mock.patch.object(oauth_service, "is_configured", return_value=True), \
                mock.patch.object(oauth_service, "verify_state", return_value=True), \
                mock.patch.object(
                    oauth_service,
                    "complete_login",
                    side_effect=oauth_service.OAuthError("no_verified_email"),
                ):
            response = self._get("/api/auth/oauth/google/callback", code="abc", state="xyz")

        self.assertEqual(self._app_redirect(response), {"error": "no_verified_email"})
        self.assertEqual(self._users(), [])


class OAuthProfileTests(unittest.TestCase):
    """complete_login must only return an email the provider has verified,
    since the callback signs the caller into the account that owns it."""

    def _complete(self, provider, responses):
        client = mock.MagicMock()
        client.__enter__.return_value = client
        client.get.side_effect = lambda url: mock.Mock(json=mock.Mock(return_value=responses[url]))
        with mock.patch.object(oauth_service, "_exchange_code", return_value="tok"), \
                mock.patch.object(oauth_service.httpx, "Client", return_value=client), \
                mock.patch.object(oauth_service.httpx, "post", side_effect=AssertionError):
            return oauth_service.complete_login(provider, "code")

    def _google(self, info):
        return self._complete(
            "google", {"https://openidconnect.googleapis.com/v1/userinfo": info}
        )

    def _github(self, user, emails):
        return self._complete(
            "github",
            {"https://api.github.com/user": user, "https://api.github.com/user/emails": emails},
        )

    def test_google_verified_email_is_returned(self):
        result = self._google({"email": "a@example.com", "email_verified": True, "name": "A"})

        self.assertEqual(result, ("a@example.com", "A"))

    def test_google_unverified_or_unstated_email_is_rejected(self):
        for info in (
            {"email": "a@example.com", "email_verified": False},
            {"email": "a@example.com"},
            {"email_verified": True},
        ):
            with self.subTest(info=info), \
                    self.assertRaisesRegex(oauth_service.OAuthError, "^no_email$"):
                self._google(info)

    def test_github_uses_the_primary_verified_email(self):
        result = self._github(
            {"login": "octo", "name": None, "email": "public@example.com"},
            [
                {"email": "other@example.com", "primary": False, "verified": True},
                {"email": "primary@example.com", "primary": True, "verified": True},
            ],
        )

        self.assertEqual(result, ("primary@example.com", "octo"))

    def test_github_without_a_primary_verified_email_is_rejected(self):
        # The profile's public email is not proof of ownership on its own.
        for emails in (
            [{"email": "p@example.com", "primary": True, "verified": False}],
            [{"email": "v@example.com", "primary": False, "verified": True}],
            [],
        ):
            with self.subTest(emails=emails), \
                    self.assertRaisesRegex(oauth_service.OAuthError, "^no_email$"):
                self._github({"login": "octo", "email": "public@example.com"}, emails)


if __name__ == "__main__":
    unittest.main()
