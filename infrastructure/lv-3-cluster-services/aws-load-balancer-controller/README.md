# AWS Load Balancer Controller

This lv-3 stack creates a least-privilege IRSA role and installs AWS Load
Balancer Controller in `kube-system` through its official Helm chart.

The controller watches Kubernetes Ingress resources and creates/manages the AWS
ALB data plane. Installing this stack alone does **not** create an ALB; the ALB
is created only after an eligible Ingress is applied.

## Deploy

Refresh kubeconfig and verify the active cluster:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name 352-demo-dev-eks \
  --alias 352-demo-dev-eks

kubectl config current-context
```

Review and apply the Terraform stack:

```bash
cd infrastructure/lv-3-cluster-services/aws-load-balancer-controller
terraform init
terraform plan
terraform apply
```

## Verify

```bash
kubectl get deployment aws-load-balancer-controller \
  --namespace kube-system

kubectl get pods \
  --namespace kube-system \
  --selector app.kubernetes.io/name=aws-load-balancer-controller \
  --output wide

kubectl get ingressclass alb
```

The controller Pods are pinned to the small `workload=core` worker and do not
need a GPU.

The chart also selects the worker security group with the additional tag
`Name=<cluster-name>-node`. This disambiguates it from the EKS primary security
group when both security groups are attached to a worker ENI and both have the
standard Kubernetes cluster tag.

## Cost and lifecycle

The controller itself runs on the existing core worker. An AWS ALB starts
incurring AWS charges only after an Ingress such as the session-3 networking
example is applied. Delete the Ingress before destroying this stack so the
controller can remove the ALB and its related resources cleanly.

Official documentation:

- https://kubernetes-sigs.github.io/aws-load-balancer-controller/
- https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html
