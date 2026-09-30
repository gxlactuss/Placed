from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings

JWT_SECRET_MIN_LENGTH = 32
# Placeholders that have shipped in this repo; they are public, so never accept them.
_PUBLIC_JWT_SECRETS = {"CHANGE_ME_IN_ENV", "replace-with-a-long-random-string"}
_GENERATE_JWT_SECRET = 'python -c "import secrets; print(secrets.token_urlsafe(48))"'


class Settings(BaseSettings):
    app_name: str = "Placement Prep API"
    # Level for the app's own loggers (app.*); uvicorn's loggers are separate.
    log_level: str = "INFO"
    database_url: str = "sqlite:///./placement_prep.db"

    # Signs access tokens and OAuth state. No usable default: an empty value is
    # rejected by _check_jwt_secret_key, so startup fails until one is set.
    jwt_secret_key: str = Field(default="", validate_default=True)
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24

    gemini_api_key: str = ""
    gemini_model: str = "gemini-flash-latest"
    gemini_fallback_models: str = (
        "gemini-3.5-flash,gemini-flash-lite-latest,gemini-3.5-flash-lite,gemini-3.1-flash-lite"
    )

    groq_api_key: str = ""
    groq_base_url: str = "https://api.groq.com/openai/v1"
    groq_model: str = "openai/gpt-oss-120b"
    groq_fallback_models: str = "openai/gpt-oss-20b"
    groq_transcription_model: str = "whisper-large-v3-turbo"
    max_audio_upload_bytes: int = 10 * 1024 * 1024

    @staticmethod
    def _split(csv: str) -> list[str]:
        return [name.strip() for name in csv.split(",") if name.strip()]

    @property
    def gemini_model_chain(self) -> list[str]:
        names = [self.gemini_model] + self._split(self.gemini_fallback_models)
        seen: set[str] = set()
        return [n for n in names if not (n in seen or seen.add(n))]

    @property
    def llm_chain(self) -> list[tuple[str, str]]:
        chain: list[tuple[str, str]] = []
        if self.groq_api_key:
            for model in [self.groq_model] + self._split(self.groq_fallback_models):
                chain.append(("groq", model))
        if self.gemini_api_key:
            for model in self.gemini_model_chain:
                chain.append(("gemini", model))
        seen: set[tuple[str, str]] = set()
        return [c for c in chain if not (c in seen or seen.add(c))]

    resend_api_key: str = ""
    email_from: str = "PlacementPrep <onboarding@resend.dev>"
    verification_code_ttl_minutes: int = 15
    # Local dev only: a fixed OTP with no expiry that skips sending email.
    # Must be empty in production (see _check_dev_verification_code).
    dev_verification_code: str = ""

    google_client_id: str = ""
    google_client_secret: str = ""
    github_client_id: str = ""
    github_client_secret: str = ""
    oauth_redirect_base: str = "http://localhost:8000"
    app_redirect_scheme: str = "placementprep"

    # Auth rate limits (limits syntax, ";"-separated). IP limits use Fly-Client-IP;
    # verify/resend/delete-account are keyed per user. "memory://" resets on restart and is not
    # shared across machines; use a redis:// URI before running more than one.
    rate_limit_enabled: bool = True
    rate_limit_storage_uri: str = "memory://"
    rate_limit_login: str = "5/minute;30/hour"
    rate_limit_signup: str = "3/minute;20/hour"
    rate_limit_verify: str = "5/minute;20/hour"
    rate_limit_resend_verification: str = "1/minute;5/hour"
    rate_limit_oauth: str = "20/minute"
    rate_limit_delete_account: str = "5/hour"

    # CORS only matters for browser clients; the iOS app is unaffected.
    # List exact origins (e.g. ["https://app.example.com"]); empty = no cross-origin access.
    cors_origins: list[str] = []
    cors_allow_credentials: bool = False

    @field_validator("jwt_secret_key")
    @classmethod
    def _check_jwt_secret_key(cls, value: str) -> str:
        secret = value.strip()
        if not secret:
            problem = "is not set"
        elif secret in _PUBLIC_JWT_SECRETS:
            problem = "is still the public placeholder value"
        elif len(secret) < JWT_SECRET_MIN_LENGTH:
            problem = f"is too short ({len(secret)} characters)"
        else:
            return value
        raise ValueError(
            f"JWT_SECRET_KEY {problem}. It signs access tokens and OAuth state, so it "
            f"must be a private random string of at least {JWT_SECRET_MIN_LENGTH} "
            "characters. Set it in backend/.env or the environment; generate one with: "
            f"{_GENERATE_JWT_SECRET}"
        )

    @model_validator(mode="after")
    def _check_cors(self) -> "Settings":
        if self.cors_allow_credentials and "*" in self.cors_origins:
            raise ValueError(
                'CORS_ORIGINS must list exact origins, not "*", when '
                "CORS_ALLOW_CREDENTIALS is true (otherwise any website gets "
                "credentialed cross-origin access)."
            )
        return self

    @model_validator(mode="after")
    def _check_dev_verification_code(self) -> "Settings":
        if self.dev_verification_code and self.resend_api_key:
            raise ValueError(
                "DEV_VERIFICATION_CODE must be empty when RESEND_API_KEY is set: "
                "a fixed verification code lets anyone verify any email address. "
                "Use it only for local development without email."
            )
        return self

    class Config:
        env_file = ".env"
        # Keep rejected values (e.g. a too-short secret) out of startup tracebacks.
        hide_input_in_errors = True


settings = Settings()
