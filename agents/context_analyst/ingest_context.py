#!/usr/bin/env python3
"""Ingest market context into the VectorStore via the Context Analyst agent.

The Context Analyst (Strands Agent with FAST_MODEL) summarizes the raw text
and upserts the result into ChromaDB (local) or Milvus/OpenSearch (EKS).

Usage:
    # Ingest a single piece of text
    python agents/context_analyst/ingest_context.py --asset BTC --source news --text "Bitcoin ETF..."

    # Pipe from stdin
    echo "BTC broke above $85k on heavy volume..." | python agents/context_analyst/ingest_context.py

    # Ingest a sample batch (useful for testing RAG before running the agent)
    python agents/context_analyst/ingest_context.py --sample

    # Fetch REAL news from Tavily and ingest (requires TAVILY_API_KEY in .env)
    python agents/context_analyst/ingest_context.py --fetch-news
    python agents/context_analyst/ingest_context.py --fetch-news --asset ETH

After ingesting, run the agent with USE_RAG=true to see the Strategist query
the vector DB via query_vectordb() before making decisions.
"""
import argparse
import asyncio
import os
import sys
from datetime import datetime, timezone

import httpx
from dotenv import load_dotenv

load_dotenv()

from agents.context_analyst.agent import ingest_context

SAMPLE_CONTEXTS = [
    {
        "asset": "BTC",
        "source": "news",
        "text": (
            "Bitcoin broke above $85,000 resistance on strong volume (2.3x daily average). "
            "Institutional buyers reported accumulating via Coinbase Prime. "
            "BTC ETF net inflows: +$420M in the last 24h. "
            "On-chain: exchange outflows spiked, suggesting accumulation not distribution."
        ),
    },
    {
        "asset": "BTC",
        "source": "technical",
        "text": (
            "BTC 4h chart: clean breakout above the $84,500 descending trendline. "
            "RSI reset from 72 to 58 during the consolidation — not overbought. "
            "Volume profile shows strong support at $82,500. "
            "MACD: bullish crossover confirmed on the 4h. "
            "Next resistance: $87,200 (March 2026 highs)."
        ),
    },
    {
        "asset": "BTC",
        "source": "signal_log",
        "text": (
            "Past 5 signals on BTC 15min: 3 GO (all profitable, avg +8.4% EV), "
            "2 NO_GO (correct calls — both would have been losers). "
            "Best performing setup: bullish MACD crossover + RSI < 40 + positive news. "
            "Worst performing: signals taken during low-volume weekend sessions."
        ),
    },
]


async def fetch_and_ingest_tavily_news(asset: str = "BTC") -> None:
    """Fetch real news from Tavily API and ingest into the vector store.

    Uses the same Tavily API as the web_search MCP server, but called directly
    so this CLI script works without Docker/MCP running.
    """
    api_key = os.getenv("TAVILY_API_KEY", "")
    if not api_key:
        print("[fetch-news] ERROR: TAVILY_API_KEY is not set in .env")
        print("  Get a free key at https://tavily.com and add it to .env")
        sys.exit(1)

    date_str = datetime.now(timezone.utc).strftime("%B %Y")
    queries = [
        f"{asset} crypto news {date_str}",
        f"{asset} price analysis {date_str}",
        f"{asset} institutional bitcoin {date_str}",
    ]

    print(f"[fetch-news] Fetching {asset} news from Tavily ({date_str})...")

    all_articles: list[str] = []
    async with httpx.AsyncClient(timeout=20.0) as client:
        for query in queries:
            try:
                response = await client.post(
                    "https://api.tavily.com/search",
                    json={
                        "api_key": api_key,
                        "query": query,
                        "max_results": 5,
                        "search_depth": "basic",
                        "include_answer": True,
                    },
                )
                response.raise_for_status()
                data = response.json()

                answer = data.get("answer", "")
                if answer:
                    all_articles.append(f"Summary: {answer}")

                for result in data.get("results", []):
                    title = result.get("title", "")
                    content = result.get("content", "")[:400]
                    published = result.get("published_date", "")
                    if title:
                        all_articles.append(f"[{published}] {title}: {content}")

                print(f"  ✓ {query}: {len(data.get('results', []))} articles")
            except Exception as exc:
                print(f"  ✗ {query}: {exc}")

    if not all_articles:
        print("[fetch-news] No articles fetched. Check your TAVILY_API_KEY.")
        sys.exit(1)

    raw_text = "\n\n".join(all_articles)
    print(f"\n[fetch-news] Ingesting {len(all_articles)} articles into vector store...")
    summary = await ingest_context(raw_text=raw_text, asset=asset, source="tavily_news")
    print(f"\n[Context Analyst] Summary:\n{summary}")
    print(f"\n[fetch-news] Done. {asset} news ingested from Tavily.")


async def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest market context into the vector store.")
    parser.add_argument("--asset", default="BTC", help="Asset (BTC, ETH, SOL)")
    parser.add_argument("--source", default="manual", help="Source label (news, technical, etc.)")
    parser.add_argument("--text", help="Raw text to ingest (or pipe via stdin)")
    parser.add_argument("--sample", action="store_true", help="Ingest built-in sample contexts")
    parser.add_argument(
        "--fetch-news",
        action="store_true",
        help="Fetch real news from Tavily API and ingest (requires TAVILY_API_KEY)",
    )
    args = parser.parse_args()

    if args.fetch_news:
        await fetch_and_ingest_tavily_news(asset=args.asset)
        return

    if args.sample:
        print(f"[ingest_context] Ingesting {len(SAMPLE_CONTEXTS)} sample contexts...\n")
        for ctx in SAMPLE_CONTEXTS:
            summary = await ingest_context(
                raw_text=ctx["text"],
                asset=ctx["asset"],
                source=ctx["source"],
            )
            print(f"Summary:\n{summary}\n{'-' * 60}\n")
        print("[ingest_context] Done. Run the agent with USE_RAG=true to use this context.")
        return

    raw_text = args.text
    if not raw_text:
        if not sys.stdin.isatty():
            raw_text = sys.stdin.read().strip()
        else:
            raw_text = input("Enter context text to ingest:\n> ").strip()

    if not raw_text:
        print("No text provided. Use --text or pipe via stdin.")
        sys.exit(1)

    summary = await ingest_context(raw_text=raw_text, asset=args.asset, source=args.source)
    print(f"\n[Context Analyst] Summary:\n{summary}")
    print("\nDone. Run with USE_RAG=true to use this context in the agent.")


if __name__ == "__main__":
    asyncio.run(main())
