import os
import unittest
from unittest import mock

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.core.config import Settings, settings
from app.core.cors import cors_options

EVIL = "https://evil.example"
GOOD = "https://app.example.com"


def make_settings(**overrides) -> Settings:
    """Settings isolated from backend/.env and any CORS_* environment variables."""
    env = {k: v for k, v in os.environ.items() if not k.upper().startswith("CORS_")}
    with mock.patch.dict(os.environ, env, clear=True):
        return Settings(_env_file=None, **overrides)


def make_client(cfg: Settings) -> TestClient:
    """A fresh app per test, so nothing leaks into the shared app.main.app."""
    app = FastAPI()
    app.add_middleware(CORSMiddleware, **cors_options(cfg))

    @app.get("/ping")
    def ping():
        return {"ok": True}

    return TestClient(app)


def preflight(client: TestClient, origin: str):
    return client.options(
        "/ping",
        headers={
            "Origin": origin,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "Authorization",
        },
    )


class CorsTests(unittest.TestCase):

    def test_default_denies_cross_origin(self):
        cfg = make_settings()
        self.assertEqual(cfg.cors_origins, [])
        self.assertFalse(cfg.cors_allow_credentials)

        client = make_client(cfg)
        response = preflight(client, EVIL)
        self.assertNotIn("access-control-allow-origin", response.headers)
        self.assertNotIn("access-control-allow-credentials", response.headers)

        response = client.get("/ping", headers={"Origin": EVIL, "Cookie": "a=b"})
        self.assertNotIn("access-control-allow-origin", response.headers)
        self.assertNotIn("access-control-allow-credentials", response.headers)

    def test_explicit_origin_is_echoed_only_for_that_origin(self):
        client = make_client(make_settings(cors_origins=[GOOD]))

        response = preflight(client, GOOD)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["access-control-allow-origin"], GOOD)
        self.assertNotIn("access-control-allow-credentials", response.headers)

        response = client.get("/ping", headers={"Origin": GOOD})
        self.assertEqual(response.headers["access-control-allow-origin"], GOOD)

        response = preflight(client, EVIL)
        self.assertNotIn("access-control-allow-origin", response.headers)
        response = client.get("/ping", headers={"Origin": EVIL})
        self.assertNotIn("access-control-allow-origin", response.headers)

    def test_explicit_origin_with_credentials(self):
        client = make_client(make_settings(cors_origins=[GOOD], cors_allow_credentials=True))
        response = preflight(client, GOOD)
        self.assertEqual(response.headers["access-control-allow-origin"], GOOD)
        self.assertEqual(response.headers["access-control-allow-credentials"], "true")
        self.assertNotIn("access-control-allow-origin", preflight(client, EVIL).headers)

    def test_wildcard_with_credentials_is_rejected(self):
        with self.assertRaises(ValidationError) as ctx:
            make_settings(cors_origins=["*"], cors_allow_credentials=True)
        self.assertIn("CORS_ORIGINS", str(ctx.exception))

    def test_wildcard_without_credentials_is_allowed(self):
        client = make_client(make_settings(cors_origins=["*"]))
        response = preflight(client, EVIL)
        self.assertEqual(response.headers["access-control-allow-origin"], "*")
        self.assertNotIn("access-control-allow-credentials", response.headers)

    def test_main_app_uses_cors_options(self):
        from app.main import app

        cors = [m for m in app.user_middleware if m.cls is CORSMiddleware]
        self.assertEqual(len(cors), 1)
        self.assertEqual(cors[0].kwargs, cors_options(settings))


if __name__ == "__main__":
    unittest.main()
