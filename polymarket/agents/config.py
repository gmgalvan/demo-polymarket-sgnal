"""
Agent configuration.

LOCAL:  uses ANTHROPIC_API_KEY directly via LiteLLM
EKS:    set MODEL_PROVIDER=litellm_proxy and point to LITELLM_API_BASE
        Agent code does not change — only this file.
"""
import os
from dotenv import load_dotenv

load_dotenv()


def _env_bool(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}

# ── Model ──────────────────────────────────────────────────────────────────────
# Local: "anthropic/claude-haiku-4-5-20251001" (cheap, fast for testing)
# EKS:   "llama-3.1-70b" (or whichever model is deployed in vLLM)
REASONING_MODEL = os.getenv("REASONING_MODEL", "anthropic/claude-haiku-4-5-20251001")
FAST_MODEL = os.getenv("FAST_MODEL", "anthropic/claude-haiku-4-5-20251001")
STRATEGIST_MAX_TOKENS = int(os.getenv("STRATEGIST_MAX_TOKENS", "768"))

MODEL_PROVIDER = os.getenv("MODEL_PROVIDER", "anthropic")  # "anthropic" | "litellm_proxy"

# LiteLLM / Anthropic
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")
LITELLM_API_BASE = os.getenv("LITELLM_API_BASE", "")
LITELLM_API_KEY = os.getenv("LITELLM_API_KEY", "")


def get_model_client_args() -> dict:
    """
    Returns client_args for LiteLLMModel based on the environment.

    Local  → Anthropic API directly
    EKS    → LiteLLM proxy (in front of vLLM GPU / Inferentia)
    """
    if MODEL_PROVIDER == "litellm_proxy":
        return {
            "api_key": LITELLM_API_KEY,
            "api_base": LITELLM_API_BASE,
            "use_litellm_proxy": True,
        }
    # default: Anthropic directly
    return {"api_key": ANTHROPIC_API_KEY}


# ── MCP Servers ───────────────────────────────────────────────────────────────
# LOCAL:  MCP servers run via docker compose (ports 8001-8003)
# EKS:    point to in-cluster service DNS names
POLYMARKET_MCP_URL = os.getenv("POLYMARKET_MCP_URL", "http://localhost:8001/sse")
TA_MCP_URL = os.getenv("TA_MCP_URL", "http://localhost:8002/sse")
SEARCH_MCP_URL = os.getenv("SEARCH_MCP_URL", "http://localhost:8003/sse")

# Whether to use real MCP servers or fall back to stub native tools
# Set USE_MCP=false to run without docker compose (Phase 1 mode)
USE_MCP = os.getenv("USE_MCP", "true").lower() == "true"

# ── RAG / Vector DB (Phase 4) ──────────────────────────────────────────────────
# Set USE_RAG=true to enable RAG: Strategist will call query_vectordb() before deciding
# Requires: ingest_context.py to have been run first (or Context Analyst background loop)
USE_RAG = os.getenv("USE_RAG", "false").lower() == "true"

# VECTOR_BACKEND: "chroma" (local, no server) | "milvus" | "opensearch" (EKS, planned)
VECTOR_BACKEND = os.getenv("VECTOR_BACKEND", "chroma")

# Path for ChromaDB persistent storage (local dev only)
CHROMA_PATH = os.getenv("CHROMA_PATH", "./data/chroma")

# ── Signal ────────────────────────────────────────────────────────────────────
DEFAULT_BANKROLL_USD = float(os.getenv("DEFAULT_BANKROLL_USD", "1000"))
HALF_KELLY = 0.5  # Use half-Kelly for conservatism
USE_LMSR = _env_bool("USE_LMSR", False)
LMSR_LIQUIDITY_B = float(os.getenv("LMSR_LIQUIDITY_B", "5000"))

# ── Graph ─────────────────────────────────────────────────────────────────────
GRAPH_EXECUTION_TIMEOUT = int(os.getenv("GRAPH_EXECUTION_TIMEOUT", "90"))
GRAPH_MAX_NODE_EXECUTIONS = 10
