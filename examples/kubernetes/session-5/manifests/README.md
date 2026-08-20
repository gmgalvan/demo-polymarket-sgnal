# manifests

Kubernetes manifests for the session-5 demo app. **Not applied to
anything yet** — this folder is ready for whenever the EKS cluster
exists. Nothing here has been run against a real or local cluster.

```
00-namespace.yaml           Namespace: session-5
01-storageclass-ebs.yaml    StorageClass: ebs-sc (gp3, dynamic provisioning)
02-mongo.yaml                PVC + Deployment + Service for MongoDB
03-backend-deployment.yaml   Deployment for api-spacy-finance (never in an Ingress)
04-frontend-deployment.yaml  Deployment for finance-chat-frontend
05-services.yaml             ClusterIP Services for backend + frontend
06-ingress.yaml               ALB Ingress: finance.example.com - frontend only
```

## Only the frontend is exposed

The backend (`api-spacy-finance`) has no Ingress rule and stays
`ClusterIP`-only — never reachable from outside the cluster. A browser
can't call it directly either way, so instead: nginx inside the
frontend Pod proxies `/health`, `/ask`, `/queries` to the backend
Service over the cluster network (see
`../finance-chat-frontend/nginx.conf.template` and the `API_UPSTREAM`
env var in `04-frontend-deployment.yaml`). One public hostname, one
ALB, no CORS needed in production, and the backend's attack surface
stays internal.

## Why EBS for Mongo, not EFS

Mongo here is a single replica that needs exclusive block storage —
that's exactly `ReadWriteOnce`, which is what EBS provides. EFS
(`ReadWriteMany`, NFS-based) is for when multiple Pods need to read/
write the *same* files concurrently — that's the model-store use case
in `session-3/3-storage/08-efs-model-store.yaml`, not a single mongod
process. Same reasoning session-3 already uses for `model-cache-ebs`
in `05-pvc-ebs-vllm.yaml`.

The PVC in `02-mongo.yaml` requests storage dynamically through the
`ebs-sc` StorageClass — Kubernetes creates the matching
PersistentVolume automatically, no hand-written PV needed.

## Before applying, once EKS exists

1. **The `aws-ebs-csi-driver` add-on** must be installed on the
   cluster (same requirement as session-3's storage lab) — otherwise
   the PVC in `02-mongo.yaml` stays `Pending` forever.
2. **Node pool labeled `workload: core`** must exist — all five
   workloads here (`mongo`, `api-spacy-finance`, `finance-chat-frontend`)
   are CPU-only and target that nodeSelector, matching the rest of this
   repo's convention for non-accelerated workloads.
3. **Images must already be in ECR** — see
   `../infra-images/README.md`. If your ECR image predates the nginx
   reverse-proxy setup (`nginx.conf.template` / `API_UPSTREAM`),
   rebuild and push it again — the old image bakes an absolute API URL
   into the bundle at Docker build time and won't work with this
   Ingress setup.

## Applying (when ready)

`${ECR_REGISTRY}` / `${IMAGE_TAG}` in the Deployments, and
`${APP_HOSTNAME}` / `${ACM_CERT_ARN}` in the Ingress, are placeholders
rendered with `envsubst`:

```bash
export ECR_REGISTRY=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-east-1.amazonaws.com
export IMAGE_TAG=latest
export APP_HOSTNAME=finance.yourdomain.com     # 06-ingress.yaml
export ACM_CERT_ARN=...                        # 06-ingress.yaml, see that file

cd examples/kubernetes/session-5/manifests
for f in *.yaml; do
  envsubst < "$f" | kubectl apply -f -
done
```

Check status:

```bash
kubectl -n session-5 get pvc,pods,svc
kubectl -n session-5 logs deploy/api-spacy-finance
```
