"""OpenSearch VectorStore — EKS backend.

Uses Amazon OpenSearch Service with k-NN (approximate nearest neighbor) search.

Authentication (selected automatically):
  OPENSEARCH_USE_IAM=true  (default on EKS)
    → AWS SigV4 via boto3 credentials (IRSA, instance profile, env vars)
  OPENSEARCH_USE_IAM=false (local dev with OpenSearch Docker or basic auth)
    → OPENSEARCH_USER / OPENSEARCH_PASSWORD

Embeddings:
  Calls the LiteLLM gateway /embeddings endpoint (same gateway used for chat).
  → LITELLM_API_BASE=http://litellm-gateway:4000
  → EMBEDDING_MODEL=nomic-embed-text  (or text-embedding-ada-002, etc.)
  → EMBEDDING_DIMENSIONS=768           (must match the model output)

Required env vars:
  OPENSEARCH_ENDPOINT   e.g. https://search-xxx.us-east-1.es.amazonaws.com
  OPENSEARCH_REGION     e.g. us-east-1
  OPENSEARCH_INDEX      default: market_context

Optional env vars:
  OPENSEARCH_USE_IAM        default: true
  OPENSEARCH_USER           only when USE_IAM=false
  OPENSEARCH_PASSWORD       only when USE_IAM=false
  LITELLM_API_BASE          default: http://localhost:4000
  EMBEDDING_MODEL           default: nomic-embed-text
  EMBEDDING_DIMENSIONS      default: 768
"""
import json
import os
from typing import Any

import httpx
from opensearchpy import OpenSearch, RequestsHttpConnection, AWSV4SignerAuth
from opensearchpy.exceptions import NotFoundError

from services.vectorstore.base import VectorStore


_INDEX_BODY = {
    "settings": {
        "index": {
            "knn": True,
            "knn.algo_param.ef_search": 100,
        }
    },
    "mappings": {
        "properties": {
            "text": {"type": "text"},
            "embedding": {
                "type": "knn_vector",
                # dimension is set dynamically in __init__
            },
            "metadata": {"type": "object", "enabled": True},
        }
    },
}


class OpenSearchVectorStore(VectorStore):
    """Amazon OpenSearch Service vector store with k-NN search."""

    def __init__(self) -> None:
        endpoint = os.environ["OPENSEARCH_ENDPOINT"].rstrip("/")
        region = os.getenv("OPENSEARCH_REGION", "us-east-1")
        self._index = os.getenv("OPENSEARCH_INDEX", "market_context")
        self._dims = int(os.getenv("EMBEDDING_DIMENSIONS", "768"))
        self._embedding_model = os.getenv("EMBEDDING_MODEL", "nomic-embed-text")
        self._litellm_base = os.getenv("LITELLM_API_BASE", "http://localhost:4000").rstrip("/")
        self._litellm_key = os.getenv("LITELLM_API_KEY", "sk-dummy")

        use_iam = os.getenv("OPENSEARCH_USE_IAM", "true").lower() not in {"false", "0", "no"}

        if use_iam:
            import boto3
            credentials = boto3.Session().get_credentials()
            auth: Any = AWSV4SignerAuth(credentials, region, "es")
            print(f"[VectorStore] OpenSearch IAM auth → {endpoint}")
        else:
            user = os.getenv("OPENSEARCH_USER", "admin")
            password = os.getenv("OPENSEARCH_PASSWORD", "admin")
            auth = (user, password)
            print(f"[VectorStore] OpenSearch basic auth → {endpoint}")

        # Parse host/port from endpoint URL
        scheme = "https" if endpoint.startswith("https") else "http"
        host_part = endpoint.replace("https://", "").replace("http://", "")
        if ":" in host_part:
            host, port_str = host_part.rsplit(":", 1)
            port = int(port_str)
        else:
            host = host_part
            port = 443 if scheme == "https" else 9200

        self._client = OpenSearch(
            hosts=[{"host": host, "port": port}],
            http_auth=auth,
            use_ssl=(scheme == "https"),
            verify_certs=True,
            connection_class=RequestsHttpConnection,
            timeout=30,
        )

        self._ensure_index()

    # ── Index setup ────────────────────────────────────────────────────────────

    def _ensure_index(self) -> None:
        if self._client.indices.exists(index=self._index):
            return
        body = json.loads(json.dumps(_INDEX_BODY))
        body["mappings"]["properties"]["embedding"]["dimension"] = self._dims
        self._client.indices.create(index=self._index, body=body)
        print(f"[VectorStore] Created OpenSearch index '{self._index}' (dims={self._dims})")

    # ── Embeddings (via LiteLLM gateway) ──────────────────────────────────────

    def _embed(self, text: str) -> list[float]:
        url = f"{self._litellm_base}/embeddings"
        payload = {"model": self._embedding_model, "input": text}
        headers = {"Authorization": f"Bearer {self._litellm_key}", "Content-Type": "application/json"}
        with httpx.Client(timeout=30) as client:
            resp = client.post(url, json=payload, headers=headers)
        resp.raise_for_status()
        data = resp.json()
        return data["data"][0]["embedding"]

    # ── VectorStore interface ──────────────────────────────────────────────────

    def upsert(self, doc_id: str, text: str, metadata: dict) -> None:
        vector = self._embed(text)
        doc = {"text": text, "embedding": vector, "metadata": metadata}
        self._client.index(index=self._index, id=doc_id, body=doc, refresh=True)

    def query(self, query: str, top_k: int = 3) -> list[dict]:
        vector = self._embed(query)
        body = {
            "size": top_k,
            "query": {
                "knn": {
                    "embedding": {
                        "vector": vector,
                        "k": top_k,
                    }
                }
            },
            "_source": ["text", "metadata"],
        }
        resp = self._client.search(index=self._index, body=body)
        results = []
        for hit in resp["hits"]["hits"]:
            results.append({
                "text": hit["_source"]["text"],
                "metadata": hit["_source"].get("metadata", {}),
                "distance": 1 - hit["_score"],  # cosine similarity → distance
            })
        return results

    def delete(self, doc_id: str) -> None:
        try:
            self._client.delete(index=self._index, id=doc_id, refresh=True)
        except NotFoundError:
            pass
