# Course log: standing up EKS for session-5

A running log of the Terraform steps actually executed against
`infrastructure/`, in order, to get the session-5 app onto a real EKS
cluster. Kept here (not in `infrastructure/`) because it's a narrative
of what we did and why, not infrastructure code itself.

Account: `111122223333` (`arn:aws:iam::111122223333:user/ggalv`)
Region: `us-east-1`
Cluster: `352-demo-dev-eks`

## 0. Prerequisites

```bash
aws sts get-caller-identity
bash infrastructure/scripts/init_backend.sh status
```

Confirmed the Terraform remote backend already existed:
- S3 bucket `352-demo-dev-s3b-tfstate-backend` (versioned, encrypted)
- DynamoDB lock table `352-demo-dev-ddb-tfstate-lock`

Checked the state of every layer directly in S3 first
(`aws s3 ls s3://352-demo-dev-s3b-tfstate-backend/dev/ --recursive`)
— every layer's state was empty (0 resources). Nothing had been
applied yet, matching the note at the top of `CLAUDE.md`.

## Fix made before applying anything

`infrastructure/modules/vpc` didn't tag subnets for ALB
auto-discovery (`kubernetes.io/role/elb`, `kubernetes.io/role/
internal-elb`, `kubernetes.io/cluster/<name>`). Without these, the AWS
Load Balancer Controller can't find subnets for an Ingress-created
ALB. Added a `eks_cluster_name` variable (default `352-demo-dev-eks`,
matching lv-2's default) and the three tags on all four subnet
resources, before the first `terraform apply`.

## 1. `lv-0-networking/vpc`

```bash
cd infrastructure/lv-0-networking/vpc
terraform init
terraform plan
terraform apply
```

Plan: 33 to add. First `apply` failed partway through:

```
Error: creating CloudWatch Logs Log Group (/aws/vpc/352-demo-dev-vpc-flow-logs):
ResourceAlreadyExistsException: The specified log group already exists
```

An orphaned log group (345 bytes, leftover from an earlier attempt)
existed in AWS but wasn't in Terraform's state. Everything else
(VPC, NAT Gateway, subnets, routes) had already been created by that
same `apply` before it hit this error. Fixed by importing the
existing resource instead of deleting it:

```bash
terraform import module.vpc.aws_cloudwatch_log_group.main[0] \
  /aws/vpc/352-demo-dev-vpc-flow-logs
terraform apply
```

Second apply: `1 added, 1 changed, 0 destroyed` (the flow log
subscription + the imported log group's tags reconciling). Done.

**Result:**
- `vpc_id = vpc-07b018557bb2b779d`
- 3 public subnets, 6 private subnets, across `us-east-1a/b/c`
- 1 NAT Gateway
- Subnets tagged for ALB auto-discovery (verified in the plan before
  applying: 3× `kubernetes.io/role/elb=1`, 6× `kubernetes.io/role/
  internal-elb=1`)

## 2. `lv-2-core-compute/eks`

```bash
cd ../../lv-2-core-compute/eks
terraform init
terraform plan -var='cluster_admin_principal_arns=["arn:aws:iam::111122223333:user/ggalv"]'
terraform apply -var='cluster_admin_principal_arns=["arn:aws:iam::111122223333:user/ggalv"]'
```

Plan: 98 to add. Reviewed before applying — 5 managed node groups
defined, only one starts with real nodes:

| Node group | Instance types | min/desired/max |
|---|---|---|
| `core` | `m7g.large/xlarge/2xlarge` (Graviton, arm64) | 1/1/2 |
| `l40s`, `gpu_fixed`, `gpu_fixed_l40s`, `inferentia` | various GPU/Inferentia | 0/0/1 (idle, no cost until scaled) |

Also created: EKS control plane, OIDC provider (needed for IRSA in
later layers), Karpenter's AWS-side prerequisites (IAM role, instance
profile, SQS interruption queue — Karpenter itself isn't installed
yet), and an access entry granting `ggalv` cluster-admin.

Applied clean, no errors this time.

**Result:**
- `cluster_name = 352-demo-dev-eks`, `cluster_version = 1.35`
- `cluster_oidc_provider_arn` — needed by aws-load-balancer-controller
  and external-dns next

```bash
aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
kubectl get nodes
```

```
NAME                         STATUS   ROLES    AGE     VERSION
ip-10-40-3-28.ec2.internal   Ready    <none>   8m44s   v1.35.6-eks-254016e
```

Confirmed it's the Graviton `core` node group:

```bash
kubectl get nodes --show-labels | grep -o 'workload=core\|kubernetes.io/arch=[a-z0-9]*'
```
```
kubernetes.io/arch=arm64
workload=core
```

## 3. `lv-3-cluster-services/aws-load-balancer-controller`

```bash
cd ../../lv-3-cluster-services/aws-load-balancer-controller
terraform init
terraform apply
```

Reads `vpc_id`, `cluster_oidc_provider_arn`, etc. from lv-2's remote
state automatically — no vars needed. `4 added, 0 changed, 0
destroyed`: IRSA policy + role + attachment, and the Helm release.

**Result:**
- `iam_role_arn = arn:aws:iam::111122223333:role/352-demo-dev-eks-aws-load-balancer-controller`
- 2 controller Pods running in `kube-system`, confirmed with:

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-load-balancer-controller
```
```
aws-load-balancer-controller-7689d49dbd-8k8xf   1/1   Running
aws-load-balancer-controller-7689d49dbd-9646n   1/1   Running
```

This is the piece that turns a Kubernetes `Ingress` object into a real
ALB — it doesn't create one yet by itself, only once we apply
`examples/kubernetes/session-5/manifests/06-ingress.yaml`.

## 4. `lv-3-cluster-services/external-dns`

```bash
cd ../external-dns
terraform init
terraform plan  -var="domain_filter=example.com"
terraform apply -var="domain_filter=example.com"
```

The module's default `hosted_zone_id` (`Z0123456789ABCDEFGHIJ`) was
already the real `example.com` zone in this account — only
`domain_filter` needed overriding (its default was the placeholder
`example.com`). Verified in the plan before applying: the generated
IAM policy scopes `route53:ChangeResourceRecordSets` to just that one
hosted zone ARN (can't touch `example.dev`, `example.net`, etc.).

`4 added, 0 changed, 0 destroyed`. Clean apply, no errors.

**Result:**
- `iam_role_arn = arn:aws:iam::111122223333:role/352-demo-dev-eks-external-dns`
- `managed_hosted_zone_id = Z0123456789ABCDEFGHIJ`

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/instance=external-dns
```
```
external-dns-7bf4bd574-m687q   1/1   Running
```

This is what turns the
`external-dns.alpha.kubernetes.io/hostname: finance.example.com`
annotation on the Ingress into an actual Route53 record pointing at
the ALB, once the Ingress is applied.

**All four infra layers are now up.** Next: deploy the app itself.

## 5. Deploying the app surfaced two real bugs — both fixed

```bash
export ECR_REGISTRY=111122223333.dkr.ecr.us-east-1.amazonaws.com
export IMAGE_TAG=latest
cd examples/kubernetes/session-5/manifests
for f in *.yaml; do envsubst < "$f" | kubectl apply -f -; done
```

All 10 objects created, but `kubectl -n session-5 get pvc,pods,svc,ingress`
showed two problems:

### Bug 1: `mongo-data` PVC stuck `Pending`

Root cause: `infrastructure/modules/eks-cluster` only installs the
`coredns`, `kube-proxy`, `vpc-cni` addons — `aws-ebs-csi-driver` was
missing, so the `ebs-sc` StorageClass had no driver to provision a
volume for. Fixed in `infrastructure/modules/eks-cluster/main.tf`:
added a dedicated IRSA role (`module.ebs_csi_irsa`, pinned to the
IAM module's 5.x line - the 6.x line needs aws provider >= 6.28,
incompatible with `terraform-aws-modules/eks/aws ~> 20.0`'s
`< 6.0.0` constraint) and an `aws_eks_addon.ebs_csi_driver` resource,
as a standalone resource (not inline `cluster_addons`) to avoid a
circular dependency: the addon's IRSA role needs
`module.eks.oidc_provider_arn`, so `module.eks` itself can't depend
on it.

Applying it hit one real snag along the way: re-running
`terraform apply` with the same `-var='cluster_admin_principal_arns=[...]'`
from step 2 failed with `ResourceInUseException: The specified access
entry resource is already in use` — turns out that access entry was
never actually created in the first EKS apply; only the automatic
`cluster_creator` entry (from `enable_cluster_creator_admin_permissions
= true`) exists, covering the exact same principal. Re-ran the apply
without that var (redundant - you already have admin via
`cluster_creator`) and it went through clean.

```bash
aws eks describe-addon --cluster-name 352-demo-dev-eks \
  --addon-name aws-ebs-csi-driver --region us-east-1 \
  --query 'addon.{name:addonName,status:status,version:addonVersion}'
```
```
{"name": "aws-ebs-csi-driver", "status": "ACTIVE", "version": "v1.63.1-eksbuild.1"}
```

*(Side note: this same apply also replaced 3 Karpenter node-role
policy attachments - pure IAM churn from an unpinned `~> 20.0` module
version resolving to a newer patch than the first apply used, nothing
to do with the EBS fix. Verified zero impact: Karpenter's controller
isn't installed in any of the 4 layers we applied, so nothing was
actually using that role. Confirmed all 4 policies re-attached after:
`AmazonSSMManagedInstanceCore`, `AmazonEKS_CNI_Policy`,
`AmazonEC2ContainerRegistryReadOnly`, `AmazonEKSWorkerNodePolicy`.)*

### Bug 2: `api-spacy-finance` pods crash-looping

Not actually crashing - `kubectl describe pod` showed
`Liveness probe failed: ... context deadline exceeded` repeatedly,
followed by `Killing ... failed liveness probe, will be restarted`.

Root cause: `/health` calls `db.ping()`, which tries to reach Mongo
with a 5s `serverSelectionTimeoutMS`. While `mongo-data` was `Pending`
(bug 1), the `mongo` Service had zero endpoints, so every `/health`
call blocked for seconds - way past the *default* probe
`timeoutSeconds` of 1s (never set explicitly in
`03-backend-deployment.yaml`). kubelet kept killing otherwise-healthy
Pods because a health check that touches a downstream dependency was
wired up as the **liveness** probe. This defeats the whole point of
the Mongo-unreachable fallback logic in `app/nlp.py` - the app was
designed to degrade gracefully, but the probe design didn't let it.

**Fix:** added `GET /livez` to `app/main.py` - no I/O, always instant,
used only for `livenessProbe`. `GET /health` (which still calls
`ping()`) stays on `readinessProbe` only, with `timeoutSeconds: 3`
added. Also dropped `serverSelectionTimeoutMS` in `app/db.py` from
5000 to 1500 so a real Mongo outage fails fast regardless. Rebuilt,
pushed, and rolled out:

```bash
cd examples/kubernetes/session-5/infra-images && make build

export ECR_REGISTRY=111122223333.dkr.ecr.us-east-1.amazonaws.com
export IMAGE_TAG=latest
cd ../manifests
envsubst < 03-backend-deployment.yaml | kubectl apply -f -
kubectl -n session-5 rollout restart deployment/api-spacy-finance
kubectl -n session-5 rollout status deployment/api-spacy-finance
```

## Result: fully working, end to end, on real infra

```bash
kubectl -n session-5 get pvc,pods,ingress
```

```
persistentvolumeclaim/mongo-data   Bound   pvc-063a4047-...   10Gi   RWO   ebs-sc

pod/api-spacy-finance-84c7b6bfc6-2d6gt   1/1  Running  0
pod/api-spacy-finance-84c7b6bfc6-6fgxf   1/1  Running  0
pod/finance-chat-frontend-...            1/1  Running
pod/finance-chat-frontend-...            1/1  Running
pod/mongo-dd487d5bc-n6jx8                1/1  Running  0

ingress.networking.k8s.io/finance-frontend   alb   finance.example.com   k8s-session5-financef-....elb.amazonaws.com
```

Tested through the real public URL (DNS → ALB → frontend Pod → nginx
proxy → backend Pod → Mongo), not port-forwarded or in-cluster:

```bash
curl http://finance.example.com/health
# {"status":"ok","model":"en_core_web_sm","hardware":"cpu","database":"ok"}

curl -X POST http://finance.example.com/ask -H "Content-Type: application/json" \
  -d '{"question": "What is compound interest?"}'
# {"question":"...","detected_term":"Compound interest","answer":"...","entities":[]}

curl http://finance.example.com/queries?limit=3
# [{"question":"What is compound interest?", ..., "matched":true, "latency_ms":5, "created_at":"..."}]
```

The last call proves the whole point of adding MongoDB in the first
place: the question that was just asked through the public ALB is
sitting in a Mongo collection on a real EBS-backed PersistentVolume.

## Layers intentionally skipped for this goal

`infrastructure/scripts/rebuild_all.sh` applies ~18 layers total
(Karpenter, cert-manager, device plugins, observability stacks,
EFS, kserve/kuberay/nim-operator, langfuse). None of those are
required to run the session-5 app or expose it — they're for the
GPU/Inferentia LLM-serving demo that's the actual subject of the talk.
`lv-1-security-and-config/secrets` is also independent and unused
here. Skipped all of them to keep cost and scope down.

## 6. `lv-3-cluster-services/acm-certificate` — HTTPS

`https://finance.example.com` didn't work up to this point - the
Ingress only opened port 80, no certificate, no 443 listener. No
cert-manager needed: the ALB Controller can reference an ACM
certificate directly by ARN, so this is a plain ACM + Route53 layer,
new folder, same structure as `external-dns` (own `backend.tf`,
`providers.tf`, `variables.tf`, `main.tf`, `outputs.tf`, state key
`dev/lv-3-cluster-services/acm-certificate/terraform.tfstate`).

```bash
cd infrastructure/lv-3-cluster-services/acm-certificate
terraform init
terraform plan
terraform apply
```

`3 to add, 0 to change, 0 to destroy`: `aws_acm_certificate` (DNS
validation) + `aws_route53_record` (the CNAME ACM needs to prove
domain ownership, created in the same `example.com` zone external-dns
already manages) + `aws_acm_certificate_validation` (blocks until ACM
actually marks it `ISSUED` - the whole apply took under a minute).

```bash
aws acm describe-certificate --certificate-arn <arn> --region us-east-1 \
  --query 'Certificate.{Status:Status,Domain:DomainName}'
# {"Status": "ISSUED", "Domain": "finance.example.com"}
```

Cost: effectively none - ACM public certificates are free when used
with an integrated service like ALB, and the ALB itself doesn't charge
differently per listener/protocol; the LCU-hour billing was already
happening.

Added 3 annotations to `examples/kubernetes/session-5/manifests/
06-ingress.yaml`:

```yaml
alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:111122223333:certificate/98e33f16-9dbb-4bea-89a9-c38b6d6cb54e
alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
alb.ingress.kubernetes.io/ssl-redirect: "443"
```

Re-applied the Ingress - same ALB, no new load balancer, the
controller just added the 443 listener to the existing one:

```bash
export ECR_REGISTRY=111122223333.dkr.ecr.us-east-1.amazonaws.com
export IMAGE_TAG=latest
cd examples/kubernetes/session-5/manifests
envsubst < 06-ingress.yaml | kubectl apply -f -
```

Verified for real:

```bash
curl https://finance.example.com/health
# {"status":"ok","model":"en_core_web_sm","hardware":"cpu","database":"ok"}

curl -o /dev/null -w "HTTP %{http_code} -> %{redirect_url}\n" http://finance.example.com/
# HTTP 301 -> https://finance.example.com:443/

curl -v https://finance.example.com/ 2>&1 | grep -i "subject:\|issuer:"
# subject: CN=finance.example.com
# issuer: C=US; O=Amazon; CN=Amazon RSA 2048 M01
```

## Next steps

Nothing blocking - the app is up and working, over HTTPS, with a
real trusted certificate. Possible follow-ups:

- Install Karpenter for real if the GPU/Inferentia side of the talk's
  demo needs on-demand accelerator nodes.
- Tear down when done (see below) to stop paying for the NAT Gateway,
  EKS control plane, and the `core` EC2 node.

## Tearing down (reverse order)

Delete the Kubernetes objects *first*, while EKS still exists - the
Ingress needs to delete its ALB, and the PVC needs to release its EBS
volume, before `terraform destroy` tears down the cluster underneath
them. Skipping this step orphans both.

```bash
kubectl -n session-5 delete ingress finance-frontend
kubectl delete namespace session-5   # takes the PVC (and its EBS volume) with it

cd infrastructure/lv-3-cluster-services/acm-certificate && terraform destroy
cd ../external-dns && terraform destroy
cd ../aws-load-balancer-controller && terraform destroy
cd ../../lv-2-core-compute/eks && terraform destroy
cd ../../lv-0-networking/vpc && terraform destroy
```
