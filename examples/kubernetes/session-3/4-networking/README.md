# Networking model and Ingress on Kubernetes

This lab explains Kubernetes networking progressively. The internal networking
steps work on the current EKS cluster and do not require a GPU. The Ingress step
is optional because it requires an Ingress Controller.

For the presenter-oriented explanation in Spanish, including the GenAI context
from the Chapter 8 reference, read [`CONCEPTS.md`](./CONCEPTS.md).

```text
CNI gives each Pod an IP
        |
Pod calls another Pod directly
        |
Service provides a stable virtual IP
        |
CoreDNS resolves the Service name
        |
EndpointSlice lists the ready backend Pods
        |
Ingress optionally routes external HTTP traffic to Services
```

## Learning objectives

- Distinguish Pod IPs, Service IPs, and external addresses.
- Explain the role of the CNI without treating it as a Service or DNS server.
- Test direct Pod-to-Pod communication.
- Use a ClusterIP Service instead of depending on ephemeral Pod IPs.
- Resolve short and fully qualified Service names through CoreDNS.
- Connect a Service selector to the addresses stored in EndpointSlices.
- Explain why an Ingress resource requires an Ingress Controller.

## 0. Verify the cluster network components

Run commands from the repository root:

```bash
kubectl config current-context

kubectl get daemonset aws-node \
  --namespace kube-system

kubectl get deployment coredns \
  --namespace kube-system

kubectl get service kube-dns \
  --namespace kube-system
```

In this EKS cluster:

- `aws-node` is the Amazon VPC CNI DaemonSet and runs on every worker node.
- The VPC CNI creates Pod network interfaces and assigns VPC addresses to Pods.
- CoreDNS answers cluster DNS queries.
- `kube-dns` is the stable Service through which Pods reach CoreDNS.

Presenter message:

> The CNI creates Pod connectivity. CoreDNS performs name resolution. Services
> provide stable virtual destinations. These are related but separate jobs.

## 1. Deploy the backend Pods and a client Pod

Create two replicas of `model-api`, one `signal-api` replica, and a diagnostic
client:

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/4-networking/01-backends.yaml

kubectl apply \
  --filename examples/kubernetes/session-3/4-networking/03-client.yaml

kubectl wait pod \
  --namespace session-3 \
  --selector lab=networking-demo \
  --for=condition=Ready \
  --timeout=120s
```

Observe that every Pod has its own IP:

```bash
kubectl get pods \
  --namespace session-3 \
  --selector lab=networking-demo \
  --output wide
```

Presenter message:

> Each Pod receives a cluster-wide IP. Containers inside the same Pod share
> one network namespace and can use `localhost`; different Pods use Pod IPs.

## 2. Demonstrate direct Pod-to-Pod communication

Capture one model Pod IP:

```bash
MODEL_POD_IP=$(kubectl get pods \
  --namespace session-3 \
  --selector app=model-api \
  --output jsonpath='{.items[0].status.podIP}')

echo "$MODEL_POD_IP"
```

Call that IP from the client Pod:

```bash
kubectl exec \
  --namespace session-3 \
  network-client -- \
  wget -qO- "http://${MODEL_POD_IP}/"
```

This request does not use a Service or DNS. It proves that the Pod network is
working, but applications should not store that IP because Pods are
replaceable.

Presenter message:

> Pod-to-Pod networking is direct, but a Pod IP is an implementation detail,
> not a durable application identity.

## 3. Add stable Services

Create one ClusterIP Service for each backend:

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/4-networking/02-services.yaml

kubectl get services \
  --namespace session-3
```

The important connection in the manifest is:

```yaml
Service selector:
  app: model-api

Pod label:
  app: model-api
```

Kubernetes creates EndpointSlices from the ready Pods matching that selector:

```bash
kubectl get endpointslices \
  --namespace session-3 \
  --selector kubernetes.io/service-name=model-api \
  --output wide
```

The Service has one stable ClusterIP while its EndpointSlice contains the two
current model Pod IPs.

## 4. Demonstrate cluster DNS

Inspect the DNS configuration received by the client Pod:

```bash
kubectl exec \
  --namespace session-3 \
  network-client -- \
  cat /etc/resolv.conf
```

Resolve the Service by its short name:

```bash
kubectl exec \
  --namespace session-3 \
  network-client -- \
  nslookup model-api
```

Call it by short name and then by its fully qualified domain name:

```bash
kubectl exec \
  --namespace session-3 \
  network-client -- \
  wget -qO- http://model-api/

kubectl exec \
  --namespace session-3 \
  network-client -- \
  wget -qO- http://model-api.session-3.svc.cluster.local/
```

The standard Service name is:

```text
<service>.<namespace>.svc.cluster.local
```

Presenter message:

> CoreDNS resolves the name to the Service ClusterIP, not directly to one Pod.
> The Service data plane then selects a ready address from its EndpointSlice.

## 5. Show why a Service is stable

Record the current Pod and Service IPs:

```bash
kubectl get pods,services \
  --namespace session-3 \
  --output wide
```

Delete one model Pod and let the Deployment replace it:

```bash
MODEL_POD=$(kubectl get pods \
  --namespace session-3 \
  --selector app=model-api \
  --output jsonpath='{.items[0].metadata.name}')

kubectl delete pod "$MODEL_POD" \
  --namespace session-3

kubectl rollout status deployment/model-api \
  --namespace session-3
```

Check the replacement Pod address and call the same Service name again:

```bash
kubectl get pods,services \
  --namespace session-3 \
  --output wide

kubectl exec \
  --namespace session-3 \
  network-client -- \
  wget -qO- http://model-api/
```

The Pod IPs can change; the Service name and ClusterIP remain stable.

## 6. Understand Ingress before applying it

Check whether an Ingress Controller is installed:

```bash
kubectl get ingressclass
```

The current cluster returns `No resources found`. Therefore, do not apply the
Ingress expecting traffic to work yet. An Ingress object contains routing
rules, but a controller must watch those rules and create/configure the real
data plane.

The optional manifest declares these routes:

```text
http://k8s.demo.example.com/model/*
  -> Service model-api:80 -> model-api Pods

http://k8s.demo.example.com/signal/*
  -> Service signal-api:80 -> signal-api Pod
```

Inspect it without creating cloud infrastructure:

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/4-networking/04-ingress-alb.yaml \
  --dry-run=server \
  --output yaml
```

Its traffic flow would be:

```text
Client
  -> AWS Application Load Balancer
  -> Ingress rule selected by HTTP path
  -> ClusterIP Service
  -> EndpointSlice
  -> ready Pod
```

The manifest uses:

```yaml
ingressClassName: alb
alb.ingress.kubernetes.io/target-type: ip
alb.ingress.kubernetes.io/scheme: internet-facing
```

- `alb` delegates reconciliation to AWS Load Balancer Controller.
- `target-type: ip` allows the ALB to target Pod IPs behind ClusterIP Services.
- `scheme: internet-facing` makes the ALB reachable from the internet. This is
  intentional for the Route 53 demo and must not be applied casually.
- The host rule accepts requests for `k8s.demo.example.com`.

After AWS Load Balancer Controller is intentionally installed and an `alb`
IngressClass exists, apply and inspect the resource:

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/4-networking/04-ingress-alb.yaml

kubectl get ingress ai-routing \
  --namespace session-3 \
  --watch
```

Before creating DNS, test the ALB address while sending the expected HTTP host:

```bash
ALB_ADDRESS=$(kubectl get ingress ai-routing \
  --namespace session-3 \
  --output jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl --header 'Host: k8s.demo.example.com' \
  "http://${ALB_ADDRESS}/model/"
```

After the test succeeds, create a Route 53 Alias record named
`k8s.demo.example.com` pointing to the ALB. No record currently exists with
that name in the public `example.com` hosted zone.

This first version uses HTTP. No ACM certificate covering `example.com` exists
in `us-east-1` yet. HTTPS requires requesting/validating an ACM certificate and
then adding the certificate ARN, listener 443, and HTTP-to-HTTPS redirect
annotations to the Ingress.

Creating an internet-facing ALB has an AWS cost and publicly exposes the demo.
Delete the Ingress when the optional exercise is finished.

Presenter message:

> Ingress is the desired HTTP routing configuration; the Ingress Controller is
> the software that turns that configuration into working infrastructure.

## 7. Upgrade the static demo to a real TinyLlama chat

The earlier backends intentionally return static HTML so the network path is
easy to observe. The optional final step keeps the same ALB and hostname, but
replaces the public routes with a small chat frontend that calls the existing
TinyLlama vLLM Service through cluster DNS:

```text
Browser -> Route 53 -> ALB -> Ingress -> signal-chat-ui Service
                                      -> Nginx frontend Pods
                                      -> tinyllama-vllm.session-3.svc.cluster.local
                                      -> TinyLlama vLLM Pod on the L40S node
```

First recreate the model ConfigMap and vLLM workload if they were removed after
the ConfigMaps lesson:

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/1-configmaps/04-file-configmap.yaml

kubectl apply \
  --filename examples/kubernetes/session-3/1-configmaps/05-volume.yaml

kubectl rollout status deployment/tinyllama-vllm \
  --namespace session-3 \
  --timeout=20m
```

Deploy the frontend and update the existing `ai-routing` Ingress. This does not
create a second ALB:

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/4-networking/05-ai-chat.yaml

kubectl rollout status deployment/signal-chat-ui \
  --namespace session-3 \
  --timeout=180s
```

Wait until the new ALB target group is healthy, then open:

```text
http://k8s.demo.example.com/
```

The browser sends `POST /api/chat` to Nginx. Nginx proxies the request internally
to `/v1/chat/completions` on the `tinyllama-vllm` ClusterIP Service. The vLLM
API is therefore not exposed as a separate public Ingress backend.

Inspect the real internal connection:

```bash
kubectl exec \
  --namespace session-3 \
  deployment/signal-chat-ui -- \
  wget -qO- http://tinyllama-vllm:8000/v1/models
```

This public chat has no authentication. Keep it only for the supervised demo
and delete the Ingress when finished.

## What each Kubernetes object contributes

| Object or component | Responsibility | Stable identity? |
|---|---|---|
| CNI (`aws-node`) | Gives Pods network connectivity and VPC IPs | Not an app endpoint |
| Pod | Runs one backend instance | No; its IP is replaceable |
| Service | Provides a stable virtual IP and name | Yes, during its lifetime |
| EndpointSlice | Tracks ready backend Pod addresses | Updated automatically |
| CoreDNS | Resolves Service names | DNS system component |
| Ingress | Declares HTTP host/path routing | Requires a controller |
| Ingress Controller | Implements the Ingress rules | Creates/configures data plane |

## Cleanup

Remove the optional Ingress first so its controller can delete any associated
load balancer:

```bash
kubectl delete --ignore-not-found \
  --filename examples/kubernetes/session-3/4-networking/05-ai-chat.yaml

kubectl delete --ignore-not-found \
  --filename examples/kubernetes/session-3/4-networking/04-ingress-alb.yaml

kubectl delete --ignore-not-found \
  --filename examples/kubernetes/session-3/4-networking/03-client.yaml \
  --filename examples/kubernetes/session-3/4-networking/02-services.yaml \
  --filename examples/kubernetes/session-3/4-networking/01-backends.yaml
```

Verify that the lesson resources are gone:

```bash
kubectl get all \
  --namespace session-3 \
  --selector lab=networking-demo
```

## References

- [Kubernetes network model](https://kubernetes.io/docs/concepts/services-networking/)
- [Kubernetes Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Amazon EKS VPC CNI](https://docs.aws.amazon.com/eks/latest/best-practices/vpc-cni.html)
- [AWS Load Balancer Controller Ingress annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/)
