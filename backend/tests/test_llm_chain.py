import unittest
from unittest.mock import MagicMock, patch

import httpx
from fastapi import HTTPException
from google.api_core import exceptions as google_exceptions

from app.ai import llm_service
from app.core.config import settings

GROQ_URL = "https://groq.test/v1/chat/completions"


def groq_reply(status: int, body=None, text: str = "") -> httpx.Response:
    request = httpx.Request("POST", GROQ_URL)
    if body is not None:
        return httpx.Response(status, json=body, request=request)
    return httpx.Response(status, text=text, request=request)


def groq_ok(content: str) -> httpx.Response:
    return groq_reply(200, {"choices": [{"message": {"content": content}}]})


class ChainTestCase(unittest.TestCase):
    """Chain is groq/g1, groq/g2, gemini/m1, gemini/m2; no real network is touched."""

    def setUp(self):
        fields = {
            "groq_api_key": "groq-test-key",
            "groq_base_url": "https://groq.test/v1",
            "groq_model": "g1",
            "groq_fallback_models": "g2",
            "gemini_api_key": "gemini-test-key",
            "gemini_model": "m1",
            "gemini_fallback_models": "m2",
        }
        for name, value in fields.items():
            patcher = patch.object(settings, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.assertEqual(
            settings.llm_chain,
            [("groq", "g1"), ("groq", "g2"), ("gemini", "m1"), ("gemini", "m2")],
        )

        post = patch.object(llm_service.httpx, "post")
        self.post = post.start()
        self.addCleanup(post.stop)

        model = patch.object(llm_service.genai, "GenerativeModel")
        self.gemini_model = model.start()
        self.addCleanup(model.stop)
        self.gemini_outcomes: dict[str, object] = {}
        self.gemini_instances: list[MagicMock] = []
        self.gemini_model.side_effect = self._make_gemini_model

    def _make_gemini_model(self, name):
        instance = MagicMock(name=f"GenerativeModel({name})")
        self.gemini_instances.append(instance)

        def generate_content(*_args, **_kwargs):
            outcome = self.gemini_outcomes[name]
            if isinstance(outcome, BaseException):
                raise outcome
            return MagicMock(text=f"  {outcome}  ")

        instance.generate_content.side_effect = generate_content
        return instance

    def groq_models_called(self) -> list[str]:
        return [c.kwargs["json"]["model"] for c in self.post.call_args_list]

    def gemini_models_called(self) -> list[str]:
        return [c.args[0] for c in self.gemini_model.call_args_list]

    def assert_http_error(self, status: int, fragment: str) -> None:
        with self.assertRaises(HTTPException) as ctx:
            llm_service._generate("prompt")
        self.assertEqual(ctx.exception.status_code, status)
        self.assertIn(fragment, ctx.exception.detail)


class GenerateChainTests(ChainTestCase):
    def test_success_on_first_model(self):
        self.post.return_value = groq_ok("<think>hmm</think>Hello there")
        self.assertEqual(llm_service._generate("prompt"), "Hello there")
        self.assertEqual(self.groq_models_called(), ["g1"])
        self.assertEqual(self.gemini_models_called(), [])

    def test_rate_limited_model_moves_to_next(self):
        self.post.side_effect = [groq_reply(429, text="rate limited"), groq_ok("from g2")]
        self.assertEqual(llm_service._generate("prompt"), "from g2")
        self.assertEqual(self.groq_models_called(), ["g1", "g2"])

    def test_groq_timeout_falls_back_to_gemini(self):
        self.post.side_effect = httpx.ReadTimeout("read timed out")
        self.gemini_outcomes["m1"] = "from gemini"
        with self.assertLogs(llm_service.logger, "WARNING") as logs:
            self.assertEqual(llm_service._generate("prompt"), "from gemini")
        self.assertEqual(self.groq_models_called(), ["g1", "g2"])
        self.assertEqual(self.gemini_models_called(), ["m1"])
        self.assertTrue(any("groq/g1" in line and "ReadTimeout" in line for line in logs.output))

    def test_groq_connect_error_falls_back(self):
        self.post.side_effect = [httpx.ConnectError("refused"), groq_ok("from g2")]
        self.assertEqual(llm_service._generate("prompt"), "from g2")

    def test_groq_server_error_falls_back(self):
        self.post.side_effect = [
            groq_reply(500, text="internal"),
            groq_reply(503, text="unavailable"),
        ]
        self.gemini_outcomes["m1"] = "from gemini"
        with self.assertLogs(llm_service.logger, "WARNING") as logs:
            self.assertEqual(llm_service._generate("prompt"), "from gemini")
        self.assertTrue(any("HTTP 500" in line for line in logs.output))

    def test_auth_rejected_skips_rest_of_provider(self):
        self.post.return_value = groq_reply(401, text="bad key")
        self.gemini_outcomes["m1"] = "from gemini"
        self.assertEqual(llm_service._generate("prompt"), "from gemini")
        self.assertEqual(self.groq_models_called(), ["g1"])

    def test_gemini_quota_moves_to_next_gemini_model(self):
        self.post.return_value = groq_reply(429, text="rate limited")
        self.gemini_outcomes["m1"] = google_exceptions.ResourceExhausted("quota")
        self.gemini_outcomes["m2"] = "from m2"
        self.assertEqual(llm_service._generate("prompt"), "from m2")

    def test_gemini_transient_moves_to_next_gemini_model(self):
        self.post.return_value = groq_reply(429, text="rate limited")
        self.gemini_outcomes["m1"] = google_exceptions.DeadlineExceeded("deadline")
        self.gemini_outcomes["m2"] = "from m2"
        self.assertEqual(llm_service._generate("prompt"), "from m2")

    def test_all_quota_returns_quota_message(self):
        self.post.return_value = groq_reply(429, text="rate limited")
        self.gemini_outcomes["m1"] = google_exceptions.ResourceExhausted("quota")
        self.gemini_outcomes["m2"] = Exception("429 You exceeded your current quota")
        self.assert_http_error(503, "usage limit")

    def test_all_transient_returns_try_again(self):
        self.post.side_effect = [httpx.ReadTimeout("slow"), groq_reply(502, text="bad gateway")]
        self.gemini_outcomes["m1"] = google_exceptions.ServiceUnavailable("down")
        self.gemini_outcomes["m2"] = google_exceptions.DeadlineExceeded("deadline")
        self.assert_http_error(503, "having trouble")

    def test_mixed_quota_and_transient_returns_try_again(self):
        self.post.return_value = groq_reply(429, text="rate limited")
        self.gemini_outcomes["m1"] = google_exceptions.ResourceExhausted("quota")
        self.gemini_outcomes["m2"] = google_exceptions.InternalServerError("oops")
        self.assert_http_error(503, "having trouble")

    def test_malformed_groq_body_returns_502_without_fallback(self):
        self.post.return_value = groq_reply(200, {"unexpected": True})
        self.assert_http_error(502, "having trouble")
        self.assertEqual(self.gemini_models_called(), [])

    def test_groq_client_error_is_not_transient(self):
        self.post.return_value = groq_reply(400, text="bad request")
        self.assert_http_error(502, "having trouble")
        self.assertEqual(self.groq_models_called(), ["g1"])

    def test_unexpected_gemini_error_returns_502(self):
        self.post.return_value = groq_reply(429, text="rate limited")
        self.gemini_outcomes["m1"] = ValueError("response blocked by safety filters")
        self.assert_http_error(502, "having trouble")
        self.assertEqual(self.gemini_models_called(), ["m1"])

    def test_empty_chain_is_not_configured(self):
        with patch.object(settings, "groq_api_key", ""), patch.object(settings, "gemini_api_key", ""):
            self.assert_http_error(503, "not configured")
        self.post.assert_not_called()
        self.gemini_model.assert_not_called()

    def test_gemini_receives_timeout(self):
        self.post.return_value = groq_reply(429, text="rate limited")
        self.gemini_outcomes["m1"] = "from gemini"
        llm_service._generate("prompt", temperature=0)
        self.assertEqual(len(self.gemini_instances), 1)
        kwargs = self.gemini_instances[0].generate_content.call_args.kwargs
        self.assertEqual(kwargs["request_options"], {"timeout": llm_service._TIMEOUT})
        self.assertEqual(kwargs["generation_config"], {"temperature": 0})

    def test_groq_receives_timeout(self):
        self.post.return_value = groq_ok("hi")
        llm_service._generate("prompt")
        self.assertEqual(self.post.call_args.kwargs["timeout"], llm_service._TIMEOUT)


if __name__ == "__main__":
    unittest.main()
