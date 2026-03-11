"""RAG tool for the Strategist — query_vectordb().

Uses the VectorStore (ChromaDB locally, Milvus/OpenSearch on EKS) to retrieve
historical market context ingested by the Context Analyst.

Only active when USE_RAG=true in .env.
"""
from strands import tool

from services.vectorstore.factory import get_vector_store


@tool
def query_vectordb(query: str, top_k: int = 3) -> str:
    """Search historical market context from the vector database.

    Retrieves relevant summaries ingested by the Context Analyst: past signal
    performance, news sentiment, key price levels, and on-chain activity.

    Call this BEFORE making your final GO/NO_GO decision.

    Args:
        query: What you're looking for (e.g. "BTC support levels", "recent sentiment")
        top_k: Number of results to return (default: 3, max: 5)
    """
    vs = get_vector_store()
    results = vs.query(query=query, top_k=min(top_k, 5))

    if not results:
        return (
            "No relevant context found in vector store. "
            "Proceed with current market data only."
        )

    lines = ["=== Historical Context (Vector DB) ==="]
    for i, item in enumerate(results, 1):
        meta = item["metadata"]
        lines.append(
            f"\n[{i}] asset={meta.get('asset', '?')} "
            f"source={meta.get('source', '?')} "
            f"time={meta.get('timestamp', 'N/A')[:16]}"
        )
        lines.append(f"    {item['text'].strip()}")

    return "\n".join(lines)
