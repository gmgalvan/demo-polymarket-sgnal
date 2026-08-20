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
├── manifests/               # Kubernetes objects, applied in numbered order
├── slides/                  # the deck, with a real embedded terminal
├── course.md                # every command run, and every error hit, verbatim
├── speaker-notes-bug-3.md   # spoken script for the database-outage demo
├── docker-compose.yml       # run the full stack locally with the ECR images
└── .env.example
```

## Running the slides

The deck lives in [slides/](slides/) and embeds a **real terminal** wired
to your own shell, so the commands on screen run against the real
cluster. That needs two processes — Vite and the pty server:

```bash
cd examples/kubernetes/session-5/slides
npm install        # first time only
npm run dev:live   # Vite + the terminal server together
```

Open the URL Vite prints (usually <http://localhost:5173>).

`npm run dev` alone also works, but every terminal panel will show
`no server — run npm run term`, and roughly half the deck depends on
those panels. Use `dev:live` when presenting.

Jump straight to a slide while rehearsing with
`?slideIndex=17`. Full details, including the colour and paste
behaviour, are in [slides/README.md](slides/README.md).

**Security note:** the pty server binds to `127.0.0.1` only. It is an
unauthenticated shell over that socket — never expose the port.

## Bring-up order (EKS)

Each step depends on the one before it. `course.md` has the same
sequence with the real output and the errors hit along the way.

**1. Network and cluster**

```bash
cd infrastructure/lv-0-networking/vpc
terraform init && terraform apply

cd ../../lv-2-core-compute/eks
terraform init
terraform apply -var='cluster_admin_principal_arns=["<your-iam-user-arn>"]'

aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
```

**2. Cluster services** — the controllers that turn Kubernetes objects
into AWS resources. These must exist *before* anything that needs them:

```bash
cd ../../lv-3-cluster-services/aws-load-balancer-controller
terraform init && terraform apply          # Ingress -> ALB

cd ../external-dns
terraform init && terraform apply -var="domain_filter=<your-zone>"

cd ../acm-certificate
terraform init && terraform apply          # the HTTPS certificate
```

**3. Images** — the manifests pull from ECR, so push before applying:

```bash
cd examples/kubernetes/session-5/infra-images
make all        # create the repos, then build+push both images (amd64+arm64)
```

**4. The application**

```bash
export ECR_REGISTRY=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com
export IMAGE_TAG=latest
export ACM_CERT_ARN=$(cd ../../../../infrastructure/lv-3-cluster-services/acm-certificate \
  && terraform output -raw certificate_arn)

cd ../manifests
for f in *.yaml; do envsubst < "$f" | kubectl apply -f -; done
```

The numeric prefixes are the order: namespace, StorageClass, Mongo (PVC
first), backend, frontend, Services, Ingress. Verify with:

```bash
kubectl -n session-5 get pvc,pods,svc,ingress
```

The ALB takes a couple of minutes to appear, and external-dns another
minute to publish the record.

## Teardown order

**Reverse the bring-up, and delete the Kubernetes objects first.** This
is not a stylistic preference — the load balancer controller is what
deletes the ALB and its security groups. Destroy that layer while an
Ingress still exists and those AWS resources are orphaned: Terraform
never knew about them, and the controller is gone. They then block the
VPC delete until you remove them by hand.

```bash
# 1. Kubernetes objects — releases the ALB and the EBS volume
kubectl delete -f examples/kubernetes/session-5/manifests/ --ignore-not-found

# wait until both are empty before continuing
kubectl get ingress -A
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'

# 2. Terraform, in reverse layer order
cd infrastructure/lv-3-cluster-services/acm-certificate && terraform destroy
cd ../external-dns                                      && terraform destroy
cd ../aws-load-balancer-controller                      && terraform destroy
cd ../../lv-2-core-compute/eks                          && terraform destroy
cd ../../lv-0-networking/vpc                            && terraform destroy

# 3. Images
cd examples/kubernetes/session-5/infra-images && make destroy
```

Then check for what Terraform never owned, because none of it shows up
as drift:

```bash
aws ec2 describe-volumes --filters Name=status,Values=available   # orphaned PVCs still bill
aws ec2 describe-addresses --query 'Addresses[?!AssociationId]'   # unassociated EIPs still bill
aws logs delete-log-group --log-group-name /aws/vpc/352-demo-dev-vpc-flow-logs
```

That last one survives the VPC destroy and will block the *next*
`apply` with "log group already exists".

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
