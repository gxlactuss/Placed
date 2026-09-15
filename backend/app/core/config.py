from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "Placement Prep API"
    database_url: str = "sqlite:///./placement_prep.db"

    jwt_secret_key: str = "CHANGE_ME_IN_ENV"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24

    gemini_api_key: str = ""
    gemini_model: str = "gemini-flash-latest"
    gemini_fallback_models: str = (
        "gemini-3.5-flash,gemini-flash-lite-latest,gemini-3.5-flash-lite,gemini-3.1-flash-lite"
    )

    groq_api_key: str = ""
    groq_base_url: str = "https://api.groq.com/openai/v1"
    groq_model: str = "llama-3.3-70b-versatile"
    groq_fallback_models: str = "openai/gpt-oss-120b,openai/gpt-oss-20b"
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
    dev_verification_code: str = "123456"

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
