"""Abstract VectorStore interface.

Implementations:
  - ChromaVectorStore  (local dev, in-process, no server needed)
  - MilvusVectorStore  (EKS, planned)
  - OpenSearchVectorStore (EKS alternative, planned)

Switch via VECTOR_BACKEND env var.
"""
from abc import ABC, abstractmethod


class VectorStore(ABC):
    @abstractmethod
    def upsert(self, doc_id: str, text: str, metadata: dict) -> None:
        """Store or update a document with its embedding."""
        ...

    @abstractmethod
    def query(self, query: str, top_k: int = 3) -> list[dict]:
        """Return top-k relevant documents for the query.

        Each result dict has: {"text": str, "metadata": dict, "distance": float}
        """
        ...

    @abstractmethod
    def delete(self, doc_id: str) -> None:
        """Remove a document by ID."""
        ...
