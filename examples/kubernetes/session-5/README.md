# Module5: Observability, Logging, Monitoring & Troubleshooting

Demo app used through this module: a small finance Q&A service
(spaCy + FastAPI backend, React frontend, MongoDB storage). It's simple
on purpose so the module can focus on observability and storage
concepts, not application complexity.

```
session-5/
├── api-spacy-finance/       # backend: FastAPI + spaCy, reads/writes MongoDB
├── finance-chat-frontend/   # frontend: React + TypeScript chat UI
├── infra-images/            # create/build/destroy the ECR repos + images
├── docker-compose.yml        # run the full stack locally with the ECR images
└── .env.example
```

## Storage: why MongoDB is here

Two collections, both explained in
[api-spacy-finance/app/db.py](api-spacy-finance/app/db.py):

- **`terms`** — the finance glossary. Seeded once from the app's
  built-in data, then read from Mongo from that point on.
- **`queries`** — a log of every question asked: what matched (or
  didn't), extracted entities, and latency. This is the concrete data
  this module points at when talking about logging/observability.

Locally, `mongo_data` is a Docker named volume. In Kubernetes, that
same role is played by a PV/PVC backed by an EBS (or EFS) volume via
the CSI driver — see `examples/kubernetes/session-3` for that half of
the story. The API itself doesn't care which one it's talking to: it
just needs a reachable `MONGO_URI`.

## Run the full stack locally (pulls images from ECR)

Requires the images to already be pushed (see
[infra-images/README.md](infra-images/README.md)):

```bash
cd examples/kubernetes/session-5

cp .env.example .env
# edit .env: set ECR_REGISTRY to <account-id>.dkr.ecr.<region>.amazonaws.com

aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin "$(grep ECR_REGISTRY .env | cut -d= -f2)"

docker compose pull
docker compose up -d
```

- Frontend: http://localhost:5173
- Backend: http://localhost:8000 (docs at `/docs`, query log at `/queries`)
- Mongo: `localhost:27017`

```bash
docker compose down          # stop, keep the mongo_data volume
docker compose down -v       # stop and wipe the data too
```
