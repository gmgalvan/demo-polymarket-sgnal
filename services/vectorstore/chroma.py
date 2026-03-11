"""ChromaDB VectorStore — local dev backend.

Two modes (selected automatically via env vars):

  Server mode (docker compose up chromadb):
    CHROMA_HOST=localhost  CHROMA_PORT=8004
    → chromadb.HttpClient — connects to the chromadb container

  In-process mode (no docker):
    CHROMA_PATH=./data/chroma  (and CHROMA_HOST not set)
    → chromadb.PersistentClient — writes directly to local directory

On EKS, swap for MilvusVectorStore or OpenSearchVectorStore via VECTOR_BACKEND.
"""
import os
from pathlib import Path

import chromadb

from services.vectorstore.base import VectorStore


class ChromaVectorStore(VectorStore):
    def __init__(self):
        host = os.getenv("CHROMA_HOST", "")
        if host:
            port = int(os.getenv("CHROMA_PORT", "8004"))
            self.client = chromadb.HttpClient(host=host, port=port)
            print(f"[VectorStore] ChromaDB server mode → {host}:{port}")
        else:
            path = str(Path(os.getenv("CHROMA_PATH", "./data/chroma")).resolve())
            Path(path).mkdir(parents=True, exist_ok=True)
            self.client = chromadb.PersistentClient(path=path)
            print(f"[VectorStore] ChromaDB in-process mode → {path}")

        self.collection = self.client.get_or_create_collection(name="market_context")

    def upsert(self, doc_id: str, text: str, metadata: dict) -> None:
        self.collection.upsert(ids=[doc_id], documents=[text], metadatas=[metadata])

    def query(self, query: str, top_k: int = 3) -> list[dict]:
        count = self.collection.count()
        if count == 0:
            return []
        n = min(top_k, count)
        results = self.collection.query(query_texts=[query], n_results=n)
        items = []
        for i, doc in enumerate(results["documents"][0]):
            items.append({
                "text": doc,
                "metadata": results["metadatas"][0][i],
                "distance": results["distances"][0][i],
            })
        return items

    def delete(self, doc_id: str) -> None:
        self.collection.delete(ids=[doc_id])
