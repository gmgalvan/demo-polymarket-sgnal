"""MongoDB access.

Two collections:
  - terms   -> the finance glossary (seeded from glossary.FINANCE_GLOSSARY
              on first run, then read from here). This is the "storage"
              half of the demo: swap this for a PV/PVC-backed MongoDB
              in Kubernetes and nothing else in the app changes.
  - queries -> a log of every question asked, what matched, and how
              long it took. This is what makes the observability story
              (session-5) concrete: you can point at real data instead
              of a hypothetical.

Every call site that touches Mongo is expected to catch
pymongo.errors.PyMongoError and degrade gracefully — a demo shouldn't
go down because the database pod isn't ready yet.
"""

import os
from functools import lru_cache

from pymongo import MongoClient
from pymongo.collection import Collection

MONGO_URI = os.environ.get("MONGO_URI", "mongodb://localhost:27017")
MONGO_DB_NAME = os.environ.get("MONGO_DB_NAME", "finance_qa")


@lru_cache(maxsize=1)
def get_client() -> MongoClient:
    # serverSelectionTimeoutMS keeps a down/slow Mongo from hanging
    # requests indefinitely - fail fast instead. Kept short (not the
    # driver's 30s default, not even 5s) because /health calls ping()
    # synchronously and is also the readiness probe target - a slow
    # failure here would delay every readiness check by that much.
    return MongoClient(MONGO_URI, serverSelectionTimeoutMS=1500)


def get_db():
    return get_client()[MONGO_DB_NAME]


def terms_collection() -> Collection:
    return get_db()["terms"]


def queries_collection() -> Collection:
    return get_db()["queries"]


def ping() -> bool:
    """Cheap connectivity check for the /health endpoint."""
    get_client().admin.command("ping")
    return True


def list_recent_queries(limit: int = 20) -> list[dict]:
    docs = queries_collection().find().sort("created_at", -1).limit(limit)
    return [
        {
            "question": d["question"],
            "detected_term": d["detected_term"],
            "matched": d["matched"],
            "latency_ms": d["latency_ms"],
            "created_at": d["created_at"].isoformat(),
        }
        for d in docs
    ]
