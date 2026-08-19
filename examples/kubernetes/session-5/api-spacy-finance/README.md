# api-spacy-finance

A **FastAPI + spaCy** API that answers basic finance questions.
It uses `en_core_web_sm`, a small model (~12 MB) that runs **CPU-only** —
no GPU or accelerator needed, so it fits well on a lightweight ARM/
Graviton-style node instead of a GPU/Inferentia node.

This is not a generative LLM: spaCy tokenizes and lemmatizes the
question, and a `PhraseMatcher` compares it against a finance glossary
to return an answer.

## Storage: MongoDB

The glossary and every question asked are persisted in MongoDB (see
[app/db.py](app/db.py)):

- **`terms`** — the glossary. Seeded once from
  [app/glossary.py](app/glossary.py) on first run, then served from
  Mongo from that point on.
- **`queries`** — a log of every `/ask` call: the question, what
  matched (if anything), extracted entities, and latency.

If Mongo is unreachable, the API keeps answering using the built-in
glossary as a fallback — it just can't log queries or serve `/queries`
until Mongo comes back (`/health` reports this via `"database"`).

| Env var         | Default                     |
|------------------|------------------------------|
| `MONGO_URI`      | `mongodb://localhost:27017` |
| `MONGO_DB_NAME`  | `finance_qa`                |

## Requirements

- [uv](https://docs.astral.sh/uv/) installed
- Python >= 3.10 (uv resolves this automatically if needed)
- A MongoDB instance reachable at `MONGO_URI` (for local dev, e.g.
  `docker run -d -p 27017:27017 mongo:7`)

## Install

```bash
cd examples/kubernetes/session-5/api-spacy-finance

# install dependencies (fastapi, uvicorn, spacy, pymongo) into a local venv
uv sync

# download the English spaCy model (CPU-only)
uv run python -m spacy download en_core_web_sm
```

## Run the API

```bash
docker run -d -p 27017:27017 mongo:7   # if you don't already have one running

uv run uvicorn app.main:app --reload --port 8000
```

The API runs at `http://localhost:8000`. Swagger UI is available at
`http://localhost:8000/docs`.

## Query the API

### Health check

Two endpoints, deliberately different:

- `GET /livez` — is the process alive? No I/O, always instant. This is
  the Kubernetes **liveness** probe target - it must never fail just
  because Mongo is down, or kubelet kills a perfectly healthy Pod for
  no reason.
- `GET /health` — is everything actually working, including Mongo?
  This is the **readiness** probe target - if Mongo is unreachable,
  the Pod correctly drops out of the Service's endpoints without being
  restarted.

```bash
curl http://localhost:8000/health
```

```json
{"status": "ok", "model": "en_core_web_sm", "hardware": "cpu", "database": "ok"}
```

### Ask a question

```bash
curl -X POST http://localhost:8000/ask \
  -H "Content-Type: application/json" \
  -d '{"question": "What is compound interest?"}'
```

```json
{
  "question": "What is compound interest?",
  "detected_term": "Compound interest",
  "answer": "Compound interest is interest calculated on the initial principal plus the accumulated interest from previous periods. That's why it grows exponentially over time.",
  "entities": []
}
```

Other example questions it recognizes: ROI, simple interest, inflation,
diversification, liquidity, leverage, EBITDA, dividends, whether to
invest in Bitcoin/crypto, and chart patterns (support and resistance,
head and shoulders, double top/bottom, triangles, candlesticks, trends).
See the full glossary in [app/glossary.py](app/glossary.py).

If the question doesn't match any glossary term, the response lists the
available topics.

### Recent queries (from MongoDB)

```bash
curl "http://localhost:8000/queries?limit=5"
```

Returns the most recent entries from the `queries` collection —
question, matched term (if any), extracted entities, and latency.
