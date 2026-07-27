from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from database.db import init_db

# One import per feature package, which is also the map of the codebase:
#   ai/      -- Groq/Gemini generation and Whisper transcription
#   auth/    -- JWT, email verification, Google and GitHub sign-in
#   content/ -- quizzes, DSA progress and company lists
# Table definitions live in the top-level `database` package, outside the app.
from app.ai import routes as interview_routes
from app.auth import oauth_routes, routes as auth_routes
from app.content import companies_routes, dsa_routes, quiz_routes


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_routes.router)
app.include_router(oauth_routes.router)
app.include_router(quiz_routes.router)
app.include_router(dsa_routes.router)
app.include_router(interview_routes.router)
app.include_router(companies_routes.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
