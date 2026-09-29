from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.core.cors import cors_options
from database.db import init_db

from app.ai import resume_routes, routes as interview_routes
from app.auth import oauth_routes, routes as auth_routes
from app.content import dsa_routes, quiz_routes


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    **cors_options(settings),
)

app.include_router(auth_routes.router)
app.include_router(oauth_routes.router)
app.include_router(quiz_routes.router)
app.include_router(dsa_routes.router)
app.include_router(interview_routes.router)
app.include_router(resume_routes.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
