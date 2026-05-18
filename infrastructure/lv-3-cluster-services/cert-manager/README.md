# cert-manager (lv-3 cluster services)

This stack installs `cert-manager` as a cluster-level dependency for controllers
that need webhook certificates, including KServe.

## Why it lives in lv-3

`cert-manager` behaves like a base cluster service rather than an inference
framework. It is shared infrastructure for webhook TLS and can support multiple
controllers beyond KServe.

## Usage

```bash
cd infrastructure/lv-3-cluster-services/cert-manager
terraform init
terraform apply
```

## Verify

```bash
kubectl get pods -n cert-manager
helm list -n cert-manager
```

Healthy components:

- `cert-manager`
- `cert-manager-webhook`
- `cert-manager-cainjector`

## Note

The cert-manager Helm chart's `startupapicheck` post-install job was flaky in
this EKS demo environment and could leave the Helm release in `failed` status
even when the core components were healthy. This stack disables that hook with:

```text
startupapicheck.enabled = false
```

For `cert-manager` chart `v1.14.5`, the CRDs are installed with:

```text
installCRDs = true
```
