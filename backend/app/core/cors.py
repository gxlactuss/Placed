from app.core.config import Settings

# Verbs the API routers actually use, plus OPTIONS for preflight.
ALLOWED_METHODS = ["GET", "POST", "PATCH", "DELETE", "OPTIONS"]
ALLOWED_HEADERS = ["Authorization", "Content-Type"]


def cors_options(settings: Settings) -> dict:
    """Keyword arguments for Starlette's CORSMiddleware."""
    return {
        "allow_origins": settings.cors_origins,
        "allow_credentials": settings.cors_allow_credentials,
        "allow_methods": ALLOWED_METHODS,
        "allow_headers": ALLOWED_HEADERS,
    }
