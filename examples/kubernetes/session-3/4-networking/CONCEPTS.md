# Guide for explaining Kubernetes networking

This guide accompanies the `4-networking` lab. It summarises the fundamentals
worth explaining during the session, and separates the advanced GenAI topics
that can be left as reference.

## The main idea

Kubernetes has to solve three distinct problems:

1. Give every Pod connectivity and an IP address.
2. Give a stable identity to an application whose Pods can change.
3. Let other components find that identity by name.

In this demo cluster, the work is divided like this:

```text
Amazon VPC CNI -> connects Pods and assigns their IPs
Service        -> provides a stable virtual IP
EndpointSlice  -> records the current addresses of ready Pods
CoreDNS        -> turns Service names into addresses
Ingress        -> declares HTTP rules for traffic entering the cluster
Controller     -> actually implements the Ingress rules
```

Suggested opening line:

> In Kubernetes, Pods are replaceable, so their IP addresses can change too. The
> network allows direct Pod-to-Pod communication, while Services and DNS provide
> the stable identity applications actually use.

## What happens when a Pod is born

A simplified but accurate enough explanation:

1. The scheduler assigns the Pod to a worker node.
2. The kubelet on that node asks the runtime to create the Pod sandbox.
3. The kubelet invokes the CNI plugin to configure its network.
4. The Amazon VPC CNI IPAM reserves an address from a VPC subnet.
5. The CNI configures the interface and the necessary routes.
6. Kubernetes publishes that address as `status.podIP`.

On EKS, `aws-node` is a DaemonSet because every worker needs a local VPC CNI
agent.

There is no need to explain ENIs, route tables or kernel rules in detail during
the first demo. It is enough to show:

```bash
kubectl get daemonset aws-node --namespace kube-system
kubectl get pods --namespace session-3 --output wide
```

## The three addresses that must not be confused

| Address | Example | Purpose | Can it change? |
|---|---|---|---|
| Pod IP | `10.40.4.101` | Identifies one concrete instance | Yes, when the Pod is replaced |
| Service ClusterIP | `172.20.50.10` | Stable virtual target inside the cluster | No, while the Service exists |
| Ingress/LB address | An ALB DNS name | HTTP entry point from another network | Managed by the controller/cloud |

Suggested message:

> A Pod IP answers "where is this replica right now?". A Service answers "how do
> I always find this application?".

## Pod-to-Pod communication

The Kubernetes model states that every Pod has its own IP and that, unless a
policy restricts it, Pods can talk to each other directly even across nodes.

Containers inside the same Pod share the network namespace:

- They share the Pod IP.
- They can reach each other over `localhost`.
- They cannot listen on the same port simultaneously.

In the demo, `network-client` calls the IP of `model-api` directly. That proves
CNI connectivity, but it is not the recommended way to configure an application,
because that IP disappears when the Pod is replaced.

## Service and EndpointSlice

A Service selects Pods by label:

```yaml
selector:
  app: model-api
```

The selected Pods carry the same label:

```yaml
labels:
  app: model-api
```

Kubernetes creates and updates EndpointSlices with the addresses of the Pods
that are ready. The Service keeps its identity even as those endpoints change.

The flow to narrate:

```text
Request to model-api:80
        -> Service model-api
        -> EndpointSlice
        -> one of the Ready Pods
```

The readiness probe matters: a backend that is not ready yet must not receive
Service traffic. In a real GenAI server, the health endpoint should signal that
the model finished loading and inference is operational.

### Service types

| Type | Typical use |
|---|---|
| `ClusterIP` | Internal communication between components; the default |
| `NodePort` | Exposes a port on every node; useful for one-off testing |
| `LoadBalancer` | Requests a load balancer from the cloud provider |
| `ExternalName` | Returns a DNS alias to an external service |

The lab uses `ClusterIP` because we want to understand internal networking first,
without creating AWS infrastructure or extra cost.

## CoreDNS and service discovery

CoreDNS lets an application use names instead of IP addresses.

Within the same namespace, this is enough:

```text
model-api
```

From any namespace, the fully qualified name works:

```text
model-api.session-3.svc.cluster.local
```

CoreDNS normally resolves that name to the Service ClusterIP. After that, the
Service data plane directs the connection to one of the ready endpoints.

Suggested message:

> DNS finds the Service; the Service finds a ready Pod. CoreDNS does not balance
> requests, and the CNI does not resolve names.

## Ingress and its controller

An Ingress is a declarative object holding HTTP/S rules. It can pick the backend
by hostname or path:

```text
/model/*  -> model-api
/signal/* -> signal-api
```

But the manifest alone moves no traffic. An Ingress Controller must watch the
object and configure the real infrastructure.

On AWS, the intended flow is:

```text
Client requests http://k8s.demo.example.com/model/
  -> Route 53
  -> Application Load Balancer
  -> /model or /signal rule
  -> Service ClusterIP
  -> EndpointSlice
  -> Pod
```

The demo uses the `alb` class and `target-type: ip`. That target type lets the
ALB register Pod addresses instead of relying on a NodePort hop. An
`internet-facing` ALB was chosen deliberately so the public name
`k8s.demo.example.com` can be attached. This costs money and exposes the demo
publicly; it must be deleted when the demonstration ends.

Route 53 only resolves the name to the ALB. It does not replace Ingress,
Service, EndpointSlice or CoreDNS. Route 53 serves the public name; CoreDNS
serves internal names such as `model-api.session-3.svc.cluster.local`.

The first version can be demonstrated over HTTP. HTTPS requires a validated ACM
certificate and a TLS listener on the ALB.

The current cluster has no `IngressClass`, so this example should be explained
without applying it until AWS Load Balancer Controller is installed on purpose.

Suggested message:

> Ingress expresses routing intent. The controller turns that intent into a real
> load balancer with real rules. Without a controller, an Ingress is just
> configuration stored in the API.

## Why this matters for GenAI

- An inference Pod can take minutes to download and load a model. Readiness
  prevents traffic from arriving too early.
- GPU Pods are replaceable too; consumers must use a Service and not cache their
  IPs.
- A platform can expose several models under one domain and route by path or
  hostname through Ingress or the Gateway API.
- Latency-sensitive inference benefits from avoiding unnecessary hops and from
  native networking such as Amazon VPC CNI.
- Large clusters need attention to IP capacity, DNS latency, throughput and
  health checks — none of which are required to understand this first demo.

## Advanced chapter topics left out of the lab

These can be mentioned at the end without being demonstrated:

- `NetworkPolicy`: L3/L4 isolation by labels, namespaces, ports and IPs.
- Service mesh: observability, mTLS, retries and L7 routing between services.
- Gateway API: a more extensible evolution for routing that also needs a
  controller.
- NodeLocal DNSCache and CoreDNS autoscaling: optimisations for clusters with
  heavy DNS query load.
- eBPF, SR-IOV, placement groups and EFA: advanced optimisations for low
  latency, high throughput or multi-node distributed training.

They do not belong in the main explanation because they distract from the
fundamental flow:

```text
Pod -> DNS -> Service -> EndpointSlice -> Pod
```

## Technical caveats from the reference material

The attached file is a paraphrased summary of the chapter, not the original PDF.
It is useful for structuring the lesson, but some statements need these caveats
before being presented as general rules:

- The runtime normally creates the Pod sandbox and network namespace; the CNI
  configures the interface, address and connectivity of that namespace. Saying
  simply that "the CNI creates the whole namespace" blurs responsibilities.
- The standard Ingress API defines host and path matching. Routing by headers,
  weights or canary depends on controller extensions or APIs such as the Gateway
  API; it is not a portable capability of basic Ingress.
- A readiness probe decides whether the Pod joins the Service's ready endpoints.
  A liveness probe can restart the container. An ALB/NLB health check
  temporarily removes a target, but on its own it does not replace the Pod.
  Three related mechanisms, not equivalents.
- Cilium can operate with different datapath modes. It should not always be
  classified as native networking without checking its actual configuration.
- The historical advice to switch kube-proxy from `iptables` to `ipvs` is
  outdated for modern Kubernetes. Kubernetes 1.35 deprecates IPVS and suggests
  evaluating `nftables` on Linux. On managed EKS the mode must not be changed
  during this class, nor without validating support and compatibility.
- Installing the managed CoreDNS add-on does not mean its autoscaling is enabled
  automatically. On EKS it is an option that must be configured and verified.
- Creating a `NetworkPolicy` object does not guarantee enforcement: the network
  plugin and its configuration must support it. Check the effective VPC CNI
  configuration before demoing it.
- VPC CNI custom networking allows alternative subnets, usually created from a
  secondary VPC CIDR. Using shared space such as `100.64.0.0/10`, its routes and
  its connectivity requires explicit design; describing any secondary CIDR as
  simply "non-routable" is not accurate.

These caveats do not change the basic lab, but they avoid presenting an advanced
optimisation as a universal property of Kubernetes.

## Common mistakes to avoid when explaining

- "A Service is another Pod": no; it is an abstraction and a virtual address.
- "CoreDNS always returns the backend IP": for a normal ClusterIP Service it
  returns the ClusterIP.
- "The CNI does load balancing": the CNI configures connectivity; it does not
  replace the Service.
- "Ingress works as soon as I apply the YAML": it needs a controller.
- "Running means ready": a Pod can be running while the model is still loading;
  what matters for traffic is `Ready`.
- "A Pod IP is permanent": it can be replaced along with the Pod.

## Five-minute short script

1. Show `aws-node` and say the CNI connects Pods and assigns their IPs.
2. Show `kubectl get pods -o wide` and call a Pod IP directly.
3. Explain why that IP is ephemeral, and create the Service.
4. Show the EndpointSlice, resolve `model-api`, and call the Service by DNS.
5. Replace a Pod, observe the new IP, and use the same Service name.
6. Close with the Ingress diagram and clarify that it requires a controller.
