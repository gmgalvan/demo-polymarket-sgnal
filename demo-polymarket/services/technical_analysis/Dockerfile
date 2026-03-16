# ── Stage 1: dependencies ─────────────────────────────────────────────────────
FROM python:3.12-slim AS deps

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

# numpy/pandas need gcc
RUN apt-get update && apt-get install -y --no-install-recommends gcc && rm -rf /var/lib/apt/lists/*

COPY services/technical_analysis/requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/
COPY --from=deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

WORKDIR /app

COPY services/technical_analysis/ .

RUN useradd -m -u 1000 mcp
USER mcp

EXPOSE 8002

CMD ["python", "server.py"]
