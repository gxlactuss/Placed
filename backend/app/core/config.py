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

    cors_origins: list[str] = ["*"]

    class Config:
        env_file = ".env"


settings = Settings()
