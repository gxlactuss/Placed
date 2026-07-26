from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "Placement Prep API"
    database_url: str = "sqlite:///./placement_prep.db"

    jwt_secret_key: str = "CHANGE_ME_IN_ENV"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24

    gemini_api_key: str = ""
    # `gemini-flash-latest` is a rolling alias to the current cheap flash model.
    # We use the alias because pinned names churn: gemini-1.5-flash was retired,
    # and free-tier keys can see `limit: 0` on gemini-2.0-flash / 404 on 2.5-flash.
    # Override via GEMINI_MODEL in .env if a specific pinned version is needed.
    gemini_model: str = "gemini-flash-latest"
    # The free tier's daily cap is **per model** (quota id
    # `GenerateRequestsPerDayPerProjectPerModel-FreeTier`), measured at 20/day
    # for gemini-3.6-flash. So exhausting one model leaves the others untouched,
    # and walking down this list buys roughly 20 more calls per entry.
    # Comma-separated; set GEMINI_FALLBACK_MODELS in .env to change.
    gemini_fallback_models: str = (
        "gemini-3.5-flash,gemini-flash-lite-latest,gemini-3.5-flash-lite,gemini-3.1-flash-lite"
    )

    # Groq is the primary LLM provider: its free tier allows on the order of
    # 14,400 requests/day against Gemini's measured 20/day, and it speaks the
    # OpenAI chat-completions API, so the whole integration is one HTTP POST.
    # Gemini stays configured as a fallback — see `llm_chain`.
    groq_api_key: str = ""
    groq_base_url: str = "https://api.groq.com/openai/v1"
    # Verified live against GET {groq_base_url}/models. Measured limits:
    # llama-3.3-70b-versatile gets 1000 requests/day and 12,000 tokens/minute;
    # the gpt-oss pair get 1000/day and 8,000 TPM — hence the ordering.
    # `qwen/qwen3.6-27b` is deliberately absent: it emits its <think> reasoning
    # trace inside `content`, which would land verbatim in the interview.
    # A retired id returns 404, which the chain treats as exhausted and skips.
    groq_model: str = "llama-3.3-70b-versatile"
    groq_fallback_models: str = "openai/gpt-oss-120b,openai/gpt-oss-20b"
    # Speech-to-text for clients that can't use Apple's on-device recogniser
    # (the Simulator has no on-device model, and the server recogniser 1101s
    # there). `-turbo` is the fast variant and plenty accurate for spoken answers.
    groq_transcription_model: str = "whisper-large-v3-turbo"
    # Groq caps uploads at 25 MB; a spoken answer is a few hundred KB, so this
    # ceiling exists to reject something pathological before we spend the call.
    max_audio_upload_bytes: int = 10 * 1024 * 1024

    @staticmethod
    def _split(csv: str) -> list[str]:
        return [name.strip() for name in csv.split(",") if name.strip()]

    @property
    def gemini_model_chain(self) -> list[str]:
        """Primary model first, then fallbacks, de-duplicated in order."""
        names = [self.gemini_model] + self._split(self.gemini_fallback_models)
        seen: set[str] = set()
        return [n for n in names if not (n in seen or seen.add(n))]

    @property
    def llm_chain(self) -> list[tuple[str, str]]:
        """(provider, model) pairs, tried in order until one answers.

        Groq first, then Gemini. Keeping a second *provider* rather than just a
        second model is deliberate: free-tier quotas are per-model **and** per
        project, so a chain within one provider still dies when that provider
        does. Only providers with a key configured appear.
        """
        chain: list[tuple[str, str]] = []
        if self.groq_api_key:
            for model in [self.groq_model] + self._split(self.groq_fallback_models):
                chain.append(("groq", model))
        if self.gemini_api_key:
            for model in self.gemini_model_chain:
                chain.append(("gemini", model))
        seen: set[tuple[str, str]] = set()
        return [c for c in chain if not (c in seen or seen.add(c))]

    # Email verification. With no RESEND_API_KEY the sender runs in dev mode and
    # logs the code to the server console (fully testable offline). Set the key
    # to send real emails via Resend; `email_from` must be a Resend-verified
    # sender (onboarding@resend.dev works to your own account email in testing).
    resend_api_key: str = ""
    email_from: str = "PlacementPrep <onboarding@resend.dev>"
    verification_code_ttl_minutes: int = 15
    # DEV/DEMO: when non-empty, every account's verification code is fixed to
    # this value and no email is sent (never expires). Set DEV_VERIFICATION_CODE=""
    # in .env to switch to real random codes emailed via Resend.
    # ⚠️ Security: a fixed code makes verification a formality — turn it off in prod.
    dev_verification_code: str = "123456"

    # Social sign-in (backend-brokered OAuth). Empty = that provider is off and
    # its button returns a "not configured" error. `oauth_redirect_base` is where
    # providers redirect back (this backend's own URL — must match the redirect
    # URI registered in each provider console); set it to the Fly URL in prod.
    # `app_redirect_scheme` is the custom URL scheme the final JWT is handed to.
    google_client_id: str = ""
    google_client_secret: str = ""
    github_client_id: str = ""
    github_client_secret: str = ""
    oauth_redirect_base: str = "http://localhost:8000"
    app_redirect_scheme: str = "placementprep"

    cors_origins: list[str] = ["*"]

    class Config:
        env_file = ".env"


settings = Settings()
