# Kubernetes Secrets: imperative and declarative creation

This short demo introduces a Kubernetes `Secret`. Secrets are intended for
sensitive values such as passwords, tokens, and API keys. Do not use real
credentials in this repository.

> Kubernetes Secrets are not encrypted automatically just because they are
> Secrets. Access control and encryption at rest must also be configured for a
> production cluster.

## Prerequisite

Run the commands from the repository root and create the namespace if needed:

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/00-namespace.yaml
```

## Option 1: imperative creation from literals

Create a Secret directly from the command line:

```bash
kubectl create secret generic model-api-credentials \
  --namespace session-3 \
  --from-literal=API_USERNAME=demo-user \
  --from-literal=API_KEY=demo-key-not-for-production
```

This approach is useful for a quick demonstration, but the command can remain
in shell history. Never type a real production secret this way.

Delete it before trying the next option with the same name:

```bash
kubectl delete secret model-api-credentials \
  --namespace session-3
```

## Option 2: imperative creation from a file

Inspect the ordinary file containing a fake API key:

```bash
cat examples/kubernetes/session-3/2-secrets/demo-api-key.txt
```

Create the Secret imperatively and use the file content as the value of the
`API_KEY` entry:

```bash
kubectl create secret generic model-api-credentials \
  --namespace session-3 \
  --from-literal=API_USERNAME=demo-user \
  --from-file=API_KEY=examples/kubernetes/session-3/2-secrets/demo-api-key.txt
```

The syntax has two different names:

```text
--from-file=<secret-key>=<local-file-path>
            API_KEY      examples/.../demo-api-key.txt
```

`API_KEY` becomes the key stored in Kubernetes. The bytes read from
`demo-api-key.txt` become its value. If the key name is omitted, kubectl uses
the local filename as the Secret key.

Inspect it before continuing:

```bash
kubectl describe secret model-api-credentials \
  --namespace session-3

kubectl get secret model-api-credentials \
  --namespace session-3 \
  --output jsonpath='{.data.API_KEY}' | base64 --decode
echo
```

Delete it before creating the same Secret declaratively:

```bash
kubectl delete secret model-api-credentials \
  --namespace session-3
```

> The file is committed only because it contains a fake classroom value. Never
> commit a file containing a real credential.

## Option 3: declarative creation from a manifest

Inspect and apply the manifest:

```bash
cat examples/kubernetes/session-3/2-secrets/01-secret.yaml

kubectl apply \
  --filename examples/kubernetes/session-3/2-secrets/01-secret.yaml
```

The manifest uses `stringData`, so the example values are readable. The API
server converts them to base64-encoded entries under `data`. Base64 is an
encoding, not encryption; never commit real credentials to Git.

## Inspect the Secret

List and describe it without displaying its values:

```bash
kubectl get secret model-api-credentials \
  --namespace session-3

kubectl describe secret model-api-credentials \
  --namespace session-3
```

For this demo only, decode the example API key:

```bash
kubectl get secret model-api-credentials \
  --namespace session-3 \
  --output jsonpath='{.data.API_KEY}' | base64 --decode
echo
```

Presenter message:

> Imperative creation can read literals or files and is useful for a quick
> demonstration. A declarative manifest is repeatable and reviewable. None of
> these methods makes a real credential safe to commit to Git; production
> environments need appropriate access controls and an external secret
> management workflow.

## Cleanup

```bash
kubectl delete secret model-api-credentials \
  --namespace session-3 \
  --ignore-not-found
```
