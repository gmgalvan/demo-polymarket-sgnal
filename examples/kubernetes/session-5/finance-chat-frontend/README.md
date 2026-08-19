# finance-chat-frontend

React + TypeScript chat UI for the [api-spacy-finance](../api-spacy-finance)
backend. Built with Vite. Lets you ask a finance question, see the
matched glossary term, the answer, and any entities spaCy extracted
from the question.

## How it reaches the backend

Two different mechanisms depending on how you're running it:

- **`npm run dev`** (this section): the app calls the backend directly,
  cross-origin, at `VITE_API_URL` (default `http://localhost:8000`).
  The backend's CORS middleware exists specifically for this case.
- **Docker image** (docker-compose, Kubernetes): the app calls
  same-origin relative paths (`/health`, `/ask`, `/queries`), and
  nginx *inside the container* proxies those to the backend at
  `API_UPSTREAM` (a runtime env var — see `nginx.conf.template` and
  the `Dockerfile`). No CORS needed, and the backend is never exposed
  directly. This is what actually runs in
  `../docker-compose.yml` and `../manifests/`.

## Requirements

- Node.js and npm
- The `api-spacy-finance` backend running (see its
  [README](../api-spacy-finance/README.md))

## Setup

```bash
cd examples/kubernetes/session-5/finance-chat-frontend
npm install
```

By default `npm run dev` calls the API at `http://localhost:8000`. To
point it somewhere else, copy `.env.example` to `.env` and set
`VITE_API_URL`.

```bash
cp .env.example .env
```

## Run

With the backend already running on port 8000 (see the backend README),
start the frontend dev server:

```bash
npm run dev
```

Open the URL Vite prints (usually `http://localhost:5173`). The header
shows a green "API online" indicator once it can reach `/health`; if
the backend isn't running yet it shows "API offline" and the input is
disabled until it comes back.

## Build

```bash
npm run build
npm run preview   # serve the production build locally
```

## Docker image

```bash
docker build -t finance-chat-frontend .
docker run -p 8080:80 -e API_UPSTREAM=host.docker.internal:8000 finance-chat-frontend
```

`API_UPSTREAM` is `host:port` of the backend, no scheme — nginx proxies
to `http://$API_UPSTREAM`. See `../docker-compose.yml`
(`API_UPSTREAM=api:8000`) and `../manifests/04-frontend-deployment.yaml`
(`API_UPSTREAM=api-spacy-finance:80`) for the two real values this
takes.
