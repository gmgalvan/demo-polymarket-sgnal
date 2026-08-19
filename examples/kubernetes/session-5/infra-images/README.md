# infra-images

Before either app can run on EKS, its image has to exist in a registry
the cluster can pull from — that's **Amazon ECR**. This folder is the
create/build/destroy lifecycle for the two ECR repositories used by
this demo:

- `api-spacy-finance` — the FastAPI + spaCy backend
- `finance-chat-frontend` — the React + TypeScript frontend

It does not deploy anything to Kubernetes — it only manages the Docker
images and the ECR repositories that hold them. The EKS manifests come
later, once the images exist.

## Requirements

- AWS CLI v2, configured with credentials that can manage ECR
  (`ecr:CreateRepository`, `ecr:DeleteRepository`, `ecr:BatchDeleteImage`,
  `ecr:*` push/pull actions) and `sts:GetCallerIdentity`.
- Docker with `buildx` (ships by default with Docker Desktop / recent
  Docker Engine). Images are built for `linux/amd64,linux/arm64` by
  default, since the whole point of this demo is that these
  CPU-only services run on Graviton (arm64) nodes.

## Configuration

All settings live in [config.env](config.env) and can be overridden as
env vars, e.g.:

```bash
AWS_REGION=us-west-2 IMAGE_TAG=v1 make create
```

| Variable        | Default                        | Meaning                                |
|-----------------|---------------------------------|-----------------------------------------|
| `AWS_REGION`    | `us-east-1`                     | Region for the ECR repositories        |
| `IMAGE_TAG`     | `latest`                        | Tag applied to both images             |
| `PLATFORMS`     | `linux/amd64,linux/arm64`       | buildx target platforms                |
| `VITE_API_URL`  | `http://localhost:8000`         | Backend URL baked into the frontend build |

The AWS account ID and registry URL are resolved automatically via
`aws sts get-caller-identity` — you don't set those.

## Usage

```bash
cd examples/kubernetes/session-5/infra-images

make create    # create the ECR repositories (idempotent)
make build     # build + push both images (multi-arch)
make list      # see what's currently pushed
make destroy   # tear everything down
```

Or step by step with `make help` to see all targets.

### Create

```bash
make create
```

Creates `api-spacy-finance` and `finance-chat-frontend` in ECR if they
don't already exist. Safe to re-run.

### Build + push

```bash
make build
```

Logs in to ECR, builds both images with `docker buildx` for
`linux/amd64` and `linux/arm64`, and pushes them straight to ECR (no
local image is kept — buildx pushes the multi-arch manifest directly).

### Destroy

```bash
make destroy
```

Deletion is deliberately two-step per repository, **not**
`delete-repository --force`:

1. List every image (tagged and untagged) in the repo and
   `batch-delete-image` them all.
2. Only once the repo is confirmed empty, delete the repository itself.

You'll be asked to type `yes` to confirm. To skip the prompt (e.g. in
CI), set `FORCE=yes`:

```bash
FORCE=yes make destroy
```

## Files

```
infra-images/
├── Makefile
├── config.env          # shared settings, override via env vars
└── scripts/
    ├── common.sh         # loads config, resolves account id/registry
    ├── create-ecr.sh
    ├── build-push.sh
    ├── list-ecr.sh
    └── destroy-ecr.sh
```
