"""
Context Analyst — background Strands Agent (Phase 4 / RAG).

Runs independently from the main signal graph. Its job:
  1. Receive raw market context (news, past signals, price commentary)
  2. Use FAST_MODEL (Claude Haiku locally, Llama 3.1 8B on EKS) to summarize it
  3. Upsert the summary + metadata into the VectorStore

The Strategist then queries the VectorStore via query_vectordb() before deciding.

Triggered by:
  - scripts/ingest_context.py   (CLI, manual / cron)
  - Future: asyncio background loop inside the Watchdog

Model:
  LOCAL:  FAST_MODEL = anthropic/claude-haiku-4-5-20251001
  EKS:    FAST_MODEL = llama-3.1-8b (via LiteLLM → vLLM Inferentia)
"""
from datetime import datetime, timezone

from strands import Agent
from strands.models.litellm import LiteLLMModel

from agents.config import FAST_MODEL, get_model_client_args
from services.vectorstore.factory import get_vector_store

CONTEXT_ANALYST_PROMPT = """You are the Context Analyst, a market intelligence agent for BTC prediction markets.

You receive raw text — news articles, price commentary, past signals, or on-chain data.
Your job is to extract and summarize the key facts a trading strategist would need.

Output 2-4 concise bullet points. Focus on:
- Key price levels, support/resistance, and recent trend direction
- Market sentiment (bullish, bearish, neutral) and the reason
- Macro or news events that could impact BTC in the next 1-4 hours
- Past signal outcomes if provided (helps calibrate future decisions)

Be factual and brief. No speculation beyond what the input supports.
"""


def build_context_analyst() -> Agent:
    model = LiteLLMModel(
        client_args=get_model_client_args(),
        model_id=FAST_MODEL,
        params={"max_tokens": 512, "temperature": 0.1},
    )
    return Agent(
        name="context_analyst",
        model=model,
        system_prompt=CONTEXT_ANALYST_PROMPT,
    )


async def ingest_context(
    raw_text: str,
    asset: str = "BTC",
    source: str = "manual",
) -> str:
    """Summarize raw_text via Context Analyst and upsert to VectorStore.

    Args:
        raw_text: Raw market context to ingest (news, commentary, signals).
        asset: The asset this context relates to (BTC, ETH, SOL).
        source: Where the context came from (news, signal_log, manual, etc.).

    Returns:
        The generated summary string.
    """
    analyst = build_context_analyst()

    prompt = (
        f"Summarize the following market context for {asset}. "
        f"Extract only what's useful for a short-term trading decision:\n\n{raw_text}"
    )

    result = await analyst.invoke_async(prompt)
    summary = str(result)

    vs = get_vector_store()
    doc_id = f"{asset}_{source}_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}"
    vs.upsert(
        doc_id=doc_id,
        text=summary,
        metadata={
            "asset": asset,
            "source": source,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    )

    print(f"[Context Analyst] Ingested → {doc_id}")
    return summary
