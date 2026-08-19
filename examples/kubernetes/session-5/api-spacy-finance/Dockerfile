# CPU-only image: no CUDA/Neuron layers, meant to run on a lightweight
# ARM/Graviton node alongside the other non-inference services.
FROM python:3.12-slim

# Install uv (single static binary, no extra deps)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

WORKDIR /app

# Install dependencies first so this layer is cached across code changes.
# README.md is copied too: pyproject.toml points `readme` at it, and
# hatchling refuses to build the package without it.
COPY pyproject.toml README.md ./
RUN uv sync --no-install-project

COPY app ./app
RUN uv sync

# Bake the spaCy model into the image so pods don't hit the network on
# every cold start.
RUN uv run python -m spacy download en_core_web_sm

EXPOSE 8000
CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
