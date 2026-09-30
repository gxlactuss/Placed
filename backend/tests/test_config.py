import os
import secrets
import unittest
from unittest import mock

from pydantic import ValidationError

from app.core.config import JWT_SECRET_MIN_LENGTH, Settings


def make_settings(env_secret: str | None = None, **overrides) -> Settings:
    """Settings isolated from backend/.env and any JWT_SECRET_KEY already in the environment."""
    env = {k: v for k, v in os.environ.items() if k.upper() != "JWT_SECRET_KEY"}
    if env_secret is not None:
        env["JWT_SECRET_KEY"] = env_secret
    with mock.patch.dict(os.environ, env, clear=True):
        return Settings(_env_file=None, **overrides)


class JwtSecretKeyTests(unittest.TestCase):

    def assert_rejected(self, expected: str, **kwargs) -> str:
        with self.assertRaises(ValidationError) as ctx:
            make_settings(**kwargs)
        message = str(ctx.exception)
        self.assertIn("JWT_SECRET_KEY", message)
        self.assertIn(expected, message)
        self.assertIn("secrets.token_urlsafe(48)", message)
        return message

    def test_missing_secret_fails(self):
        self.assert_rejected("is not set")

    def test_blank_secret_fails(self):
        self.assert_rejected("is not set", jwt_secret_key="")
        self.assert_rejected("is not set", env_secret="   ")

    def test_public_placeholders_fail(self):
        for placeholder in ("CHANGE_ME_IN_ENV", "replace-with-a-long-random-string"):
            with self.subTest(placeholder=placeholder):
                self.assert_rejected("public placeholder", jwt_secret_key=placeholder)
                self.assert_rejected("public placeholder", env_secret=placeholder)

    def test_short_secret_fails_without_echoing_it(self):
        short = "s3cret-" + "x" * (JWT_SECRET_MIN_LENGTH - 8)
        self.assertEqual(len(short), JWT_SECRET_MIN_LENGTH - 1)
        message = self.assert_rejected(
            f"too short ({JWT_SECRET_MIN_LENGTH - 1} characters)", jwt_secret_key=short
        )
        self.assertNotIn(short, message)

    def test_minimum_length_secret_is_accepted(self):
        secret = "k" * JWT_SECRET_MIN_LENGTH
        self.assertEqual(make_settings(jwt_secret_key=secret).jwt_secret_key, secret)

    def test_generated_secret_from_environment_is_accepted(self):
        secret = secrets.token_urlsafe(48)
        self.assertEqual(make_settings(env_secret=secret).jwt_secret_key, secret)


if __name__ == "__main__":
    unittest.main()
