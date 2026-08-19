from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from pymongo.errors import PyMongoError

from .db import list_recent_queries, ping
from .nlp import MODEL_NAME, answer_question, get_glossary, get_matcher, get_nlp


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Preload the model, glossary (seeds MongoDB on first run) and
    # matcher on startup, so the first request doesn't pay the cost.
    get_nlp()
    get_glossary()
    get_matcher()
    yield


app = FastAPI(
    title="Finance API with spaCy (CPU)",
    description=(
        "Answers basic finance questions using spaCy on CPU, no GPU "
        "required."
    ),
    version="0.1.0",
    lifespan=lifespan,
)

# Allow the local Vite dev server (finance-chat-frontend) to call the API.
# For a real deployment, replace "*" with the actual frontend origin(s).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class Question(BaseModel):
    question: str


@app.get("/livez")
def livez():
    """Liveness probe target: no I/O, always instant. A downstream outage
    (Mongo down) must never cause kubelet to kill this process - that's
    exactly the case the fallback logic in app/nlp.py exists to survive.
    Use /health (readiness) to reflect actual dependency status instead.
    """
    return {"status": "ok"}


@app.get("/health")
def health():
    try:
        ping()
        database_status = "ok"
    except PyMongoError:
        database_status = "unreachable"

    return {
        "status": "ok",
        "model": MODEL_NAME,
        "hardware": "cpu",
        "database": database_status,
    }


@app.post("/ask")
def ask(payload: Question):
    return answer_question(payload.question)


@app.get("/queries")
def recent_queries(limit: int = 20):
    """Recent entries from the MongoDB query log - proof that the data
    is actually persisted, not just answered and forgotten.
    """
    try:
        return list_recent_queries(limit)
    except PyMongoError:
        return []
