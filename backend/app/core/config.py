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
