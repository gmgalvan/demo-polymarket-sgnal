# ExternalDNS for Route 53

This lv-3 stack installs ExternalDNS with IRSA and limits Route 53 write access
to the existing public `example.com` hosted zone.

The deployment watches only Kubernetes Ingress resources carrying the
`external-dns.alpha.kubernetes.io/hostname` annotation. It uses a TXT registry
and a cluster-specific owner ID so it does not take ownership of unrelated DNS
records.

The default `upsert-only` policy creates and updates records but does not delete
stale records automatically. This conservative default is useful for the demo;
remove stale A/AAAA/TXT records manually after deleting an Ingress.

## Deploy

Deploy AWS Load Balancer Controller first, then run:

```bash
cd infrastructure/lv-3-cluster-services/external-dns
terraform init
terraform plan
terraform apply
```

## Verify

```bash
kubectl get deployment external-dns \
  --namespace kube-system

kubectl get pods \
  --namespace kube-system \
  --selector app.kubernetes.io/name=external-dns \
  --output wide

kubectl logs deployment/external-dns \
  --namespace kube-system \
  --tail=100
```

After applying the annotated session-3 Ingress, verify Route 53 and DNS:

```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id Z0123456789ABCDEFGHIJ \
  --query "ResourceRecordSets[?contains(Name, 'k8s.demo')]"

dig +short k8s.demo.example.com
```

ExternalDNS does not create the ALB. AWS Load Balancer Controller creates the
ALB; ExternalDNS reads its address from Ingress status and publishes the DNS
record in Route 53.

Official documentation:

- https://kubernetes-sigs.github.io/external-dns/latest/docs/tutorials/aws/
- https://kubernetes-sigs.github.io/external-dns/latest/docs/tutorials/aws-filters/
