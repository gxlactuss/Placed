from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "Placement Prep API"
    database_url: str = "sqlite:///./placement_prep.db"

    jwt_secret_key: str = "CHANGE_ME_IN_ENV"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24

    gemini_api_key: str = ""

    cors_origins: list[str] = ["*"]

    class Config:
        env_file = ".env"


settings = Settings()
