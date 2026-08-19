"""spaCy model loading and answer logic.

Model: en_core_web_sm (~12 MB, CPU-only). A small model is chosen on
purpose: it doesn't require a GPU and starts up fast, unlike the large
reasoning models (30B-70B) that this repo serves via vLLM on GPU/
Inferentia for the Polymarket agent.
"""

import sys
import time
from datetime import datetime, timezone
from functools import lru_cache

import spacy
from pymongo.errors import PyMongoError

from .db import queries_collection, terms_collection
from .glossary import (
    FINANCE_GLOSSARY,
    build_matcher,
    load_glossary_from_db,
    seed_terms,
)

MODEL_NAME = "en_core_web_sm"


def _warn(message: str) -> None:
    print(f"[api-spacy-finance] {message}", file=sys.stderr)


@lru_cache(maxsize=1)
def get_nlp():
    return spacy.load(MODEL_NAME)


@lru_cache(maxsize=1)
def get_glossary() -> dict:
    """Glossary served by the API: Mongo if reachable, static seed data
    (FINANCE_GLOSSARY) otherwise so the API still answers questions
    even if the database isn't up yet.
    """
    try:
        collection = terms_collection()
        seed_terms(collection)
        db_glossary = load_glossary_from_db(collection)
        if db_glossary:
            return db_glossary
    except PyMongoError as exc:
        _warn(f"could not load glossary from MongoDB, using built-in seed data: {exc}")
    return FINANCE_GLOSSARY


@lru_cache(maxsize=1)
def get_matcher():
    return build_matcher(get_nlp(), get_glossary())


def _extract_entities(doc) -> list[dict]:
    return [{"text": ent.text, "label": ent.label_} for ent in doc.ents]


def _best_match(doc, matcher) -> str | None:
    matches = matcher(doc)
    if not matches:
        return None
    # Keep the longest match (most specific)
    match_id, start, end = max(matches, key=lambda m: m[2] - m[1])
    return doc.vocab.strings[match_id]


def _log_query(question: str, detected_term: str | None, entities: list[dict], latency_ms: int) -> None:
    """Best-effort write to the queries collection. Logging must never
    break the API response, so any Mongo error is swallowed here.
    """
    try:
        queries_collection().insert_one(
            {
                "question": question,
                "detected_term": detected_term,
                "matched": detected_term is not None,
                "entities": entities,
                "latency_ms": latency_ms,
                "model": MODEL_NAME,
                "created_at": datetime.now(timezone.utc),
            }
        )
    except PyMongoError as exc:
        _warn(f"could not log query to MongoDB: {exc}")


def answer_question(question: str) -> dict:
    start = time.perf_counter()

    nlp = get_nlp()
    matcher = get_matcher()
    glossary = get_glossary()

    doc = nlp(question.lower())
    term_key = _best_match(doc, matcher)
    entities = _extract_entities(doc)

    if term_key is not None:
        term = glossary[term_key]
        response = {
            "question": question,
            "detected_term": term["name"],
            "answer": term["answer"],
            "entities": entities,
        }
    else:
        available_topics = ", ".join(v["name"] for v in glossary.values())
        response = {
            "question": question,
            "detected_term": None,
            "answer": (
                "I don't have information about that topic yet. "
                f"Try asking about: {available_topics}."
            ),
            "entities": entities,
        }

    latency_ms = int((time.perf_counter() - start) * 1000)
    _log_query(question, response["detected_term"], entities, latency_ms)

    return response
