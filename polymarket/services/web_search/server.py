"""
Web Search MCP Server.

Uses Tavily API to fetch recent crypto news and sentiment.
Requires TAVILY_API_KEY environment variable.

Run locally:
    TAVILY_API_KEY=tvly-... python services/web_search/server.py
"""
import os
from mcp.server.fastmcp import FastMCP
from dotenv import load_dotenv

load_dotenv()

mcp = FastMCP("Web Search MCP Server", host="0.0.0.0", port=8003)

_TAVILY_KEY = os.getenv("TAVILY_API_KEY", "")


def _get_client():
    if not _TAVILY_KEY:
        raise RuntimeError("TAVILY_API_KEY is not set")
    from tavily import TavilyClient
    return TavilyClient(api_key=_TAVILY_KEY)


def _infer_sentiment(text: str) -> str:
    """
    Naive keyword-based sentiment from titles/snippets.
    Good enough for a demo — the LLM will do the real reasoning.
    """
    text_lower = text.lower()
    bullish_words = {"rally", "surge", "gain", "bull", "high", "record", "buy", "accumulate", "inflow", "breakout"}
    bearish_words = {"crash", "drop", "fall", "bear", "low", "sell", "outflow", "dump", "fear", "hack", "ban"}

    bull_count = sum(1 for w in bullish_words if w in text_lower)
    bear_count = sum(1 for w in bearish_words if w in text_lower)

    if bull_count > bear_count:
        return "positive"
    elif bear_count > bull_count:
        return "negative"
    return "neutral"


# ── MCP Tools ─────────────────────────────────────────────────────────────────

@mcp.tool(description="Search recent crypto news and sentiment for a given asset")
def search_crypto_news(query: str, max_results: int = 5) -> dict:
    """
    Returns recent news articles and overall sentiment for the query.

    Args:
        query: Search query (e.g. "BTC institutional buying March 2026")
        max_results: Number of results to return (default 5, max 10)
    """
    if not _TAVILY_KEY:
        return {
            "query": query,
            "sentiment": "neutral",
            "articles": [],
            "error": "TAVILY_API_KEY not configured — set it in .env to enable web search",
        }

    try:
        client = _get_client()
        response = client.search(
            query=query,
            max_results=min(max_results, 10),
            search_depth="basic",
            include_answer=True,
        )
    except Exception as e:
        return {"query": query, "error": f"Tavily search failed: {e}"}

    articles = []
    all_text = ""
    for r in response.get("results", []):
        title = r.get("title", "")
        snippet = r.get("content", "")[:300]
        articles.append({
            "title": title,
            "url": r.get("url", ""),
            "snippet": snippet,
            "published_date": r.get("published_date", ""),
        })
        all_text += f" {title} {snippet}"

    sentiment = _infer_sentiment(all_text)
    answer = response.get("answer", "")

    return {
        "query": query,
        "sentiment": sentiment,
        "summary": answer,
        "articles": articles,
        "count": len(articles),
    }


@mcp.tool(description="Get a quick market sentiment summary for an asset")
def get_sentiment_summary(asset: str = "BTC") -> dict:
    """
    Runs two targeted searches and returns a combined sentiment.

    Args:
        asset: Crypto asset — "BTC", "ETH", or "SOL" (default "BTC")
    """
    from datetime import datetime
    date_str = datetime.utcnow().strftime("%B %Y")

    if not _TAVILY_KEY:
        return {
            "asset": asset,
            "sentiment": "neutral",
            "error": "TAVILY_API_KEY not configured",
        }

    try:
        client = _get_client()
        price_result = client.search(
            query=f"{asset} price prediction {date_str}",
            max_results=3,
            search_depth="basic",
        )
        news_result = client.search(
            query=f"{asset} crypto news {date_str}",
            max_results=3,
            search_depth="basic",
        )
    except Exception as e:
        return {"asset": asset, "error": f"Tavily search failed: {e}"}

    combined_text = " ".join(
        r.get("title", "") + " " + r.get("content", "")[:200]
        for r in price_result.get("results", []) + news_result.get("results", [])
    )
    sentiment = _infer_sentiment(combined_text)

    return {
        "asset": asset,
        "sentiment": sentiment,
        "top_headlines": [
            r.get("title", "") for r in
            (price_result.get("results", []) + news_result.get("results", []))[:4]
        ],
    }


if __name__ == "__main__":
    mcp.run(transport="sse")
