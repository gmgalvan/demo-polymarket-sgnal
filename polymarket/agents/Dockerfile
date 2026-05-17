# ── Stage 1: dependencies ─────────────────────────────────────────────────────
FROM python:3.12-slim AS deps

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

WORKDIR /app

COPY agents/requirements.txt .
RUN uv pip install --system --no-cache -r requirements.txt

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

# Copy uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Copy installed packages from deps stage
COPY --from=deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

WORKDIR /app

# Copy source — agents package + demo entrypoint
COPY agents/ ./agents/
COPY demo/ ./demo/

# Non-root user
RUN useradd -m -u 1000 agent
USER agent

# Default: trigger with bullish scenario (override in docker run / k8s)
# In production the Watchdog invokes the graph directly — no CLI needed
CMD ["python", "demo/trigger_local.py", "--scenario", "bullish"]
