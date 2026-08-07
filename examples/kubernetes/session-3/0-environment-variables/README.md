# Environment variables in Kubernetes

This lab introduces environment variables before adding ConfigMaps and Secrets.

The conceptual progression is:

```text
Direct value              ConfigMap                  Secret
env.value                 configMapKeyRef/envFrom    secretKeyRef
     |                           |                       |
     +---------------------------+-----------------------+
                                 |
                                Pod
```

This first exercise uses only `env.value`. The other two mechanisms come later,
to show how configuration is separated from the workload definition.

## How to explain it

Docker injects a variable when a container starts:

```bash
docker run --env APP_COLOR=lightpink busybox
```

Kubernetes expresses the same intent declaratively inside the Pod:

```yaml
env:
  - name: APP_COLOR
    value: "lightpink"
```

The image does not change. Only the configuration delivered when Kubernetes
creates the container changes.

## What the example deploys

`01-plain-env.yaml` contains:

- A Deployment with one replica.
- Two direct variables: `APP_COLOR` and `APP_MODE`.
- A small BusyBox-based HTTP server.
- A `ClusterIP` Service.

On startup, the container generates an HTML page from the environment variable
values.

## Run it

From the repository root:

```bash
kubectl apply --filename examples/kubernetes/session-3/00-namespace.yaml
kubectl apply --filename examples/kubernetes/session-3/0-environment-variables/01-plain-env.yaml

kubectl rollout status deployment/env-color-demo \
  --namespace session-3
```

## Inspect the definition

```bash
kubectl get deployment env-color-demo \
  --namespace session-3 \
  --output yaml
```

Show only the relevant section:

```bash
kubectl get deployment env-color-demo \
  --namespace session-3 \
  --output jsonpath='{.spec.template.spec.containers[0].env}'
```

## See the variables inside the container

```bash
kubectl exec \
  --namespace session-3 \
  deployment/env-color-demo -- \
  printenv APP_COLOR APP_MODE
```

Expected output:

```text
lightpink
demo
```

The complete environment can also be inspected:

```bash
kubectl exec \
  --namespace session-3 \
  deployment/env-color-demo -- \
  env
```

## See the HTTP result

In one terminal:

```bash
kubectl port-forward \
  --namespace session-3 \
  service/env-color-demo \
  8080:8080
```

In another terminal:

```bash
curl http://127.0.0.1:8080
```

`http://127.0.0.1:8080` can also be opened in a browser. The page must have a
pink background. The value of `APP_COLOR` is never printed in the HTML: its
effect is shown visually through the background colour.

## Change a variable

This command modifies the Deployment template. Kubernetes creates a new Pod,
because environment variables are set when the container starts:

```bash
kubectl set env deployment/env-color-demo \
  --namespace session-3 \
  APP_COLOR=lightgreen \
  APP_MODE=updated

kubectl rollout status deployment/env-color-demo \
  --namespace session-3
```

Check the new value:

```bash
kubectl exec \
  --namespace session-3 \
  deployment/env-color-demo -- \
  printenv APP_COLOR APP_MODE
```

Reload the page. The background must change from pink to green, without the
colour name appearing anywhere in the page text.

## Key messages

- The container image stays the same.
- `env.value` suits small, workload-specific values.
- Changing a variable in the template triggers a Deployment rollout.
- Repeating many values across several workloads creates duplication.
- A ConfigMap solves that duplication by turning configuration into an
  independent resource.
- Passwords and tokens do not belong in `env.value`.

## Transition to ConfigMaps

Suggested question for the audience:

> What happens when ten Deployments need `MODEL_PROVIDER`, `MODEL_NAME` and
> `LOG_LEVEL`, and all of them must be changed together?

The answer leads to the next lab:

```text
../1-configmaps/
```

## Cleanup

```bash
kubectl delete --filename examples/kubernetes/session-3/0-environment-variables/01-plain-env.yaml
```
