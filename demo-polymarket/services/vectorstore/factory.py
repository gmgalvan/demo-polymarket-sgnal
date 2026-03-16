"""VectorStore factory — returns the right backend based on VECTOR_BACKEND env var.

LOCAL:  VECTOR_BACKEND=chroma      (default) → ChromaVectorStore (in-process, no server)
                                               Embeddings: all-MiniLM-L6-v2 via ONNX (built-in)

EKS:    VECTOR_BACKEND=opensearch            → OpenSearchVectorStore (planned)
                                               Managed: Amazon OpenSearch Service
                                               Embeddings: LiteLLM gateway /embeddings endpoint
                                                 → routes to any embedding model (nomic-embed-text,
                                                   text-embedding-ada-002, Titan Embeddings, etc.)
                                               Same gateway already used for chat completions —
                                               no additional infrastructure needed.

Singleton — one instance per process.
"""
import os

from services.vectorstore.base import VectorStore

_instance: VectorStore | None = None


def get_vector_store() -> VectorStore:
    global _instance
    if _instance is not None:
        return _instance

    backend = os.getenv("VECTOR_BACKEND", "chroma")

    if backend == "chroma":
        from services.vectorstore.chroma import ChromaVectorStore
        _instance = ChromaVectorStore()
    else:
        raise ValueError(
            f"Unknown VECTOR_BACKEND='{backend}'. Supported: chroma (local). "
            "Set VECTOR_BACKEND=opensearch for EKS deployment."
        )

    return _instance
