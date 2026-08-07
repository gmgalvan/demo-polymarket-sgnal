# ConfigMaps for an AI model on Kubernetes

This lab introduces ConfigMaps through one progressive AI-serving example.
The first four steps run on the small ARM `core` worker. The fifth step starts
TinyLlama with vLLM and requires the NVIDIA L40S worker.

```text
01 ConfigMap with AI settings
          |
02 envFrom dashboard: consume every key
          |
03 configMapKeyRef: select only MODEL_NAME
          |
04 ConfigMap containing vllm-config.yaml
          |
05 Mount vllm-config.yaml and start TinyLlama with vLLM
```

## Learning objectives

- Separate non-sensitive configuration from a container image.
- Compare imperative and declarative ConfigMap creation.
- Inject every key with `envFrom`.
- Inject one selected key with `configMapKeyRef`.
- Create a ConfigMap from an ordinary application file.
- Mount a ConfigMap as a read-only file.
- Use mounted configuration to launch a real model server.
- Explain why ConfigMaps are not Secrets or persistent model storage.

## Prerequisites

Run commands from the repository root and confirm the active cluster:

```bash
cd ~/demo-polymarket-sgnal
kubectl config current-context
kubectl get nodes --label-columns workload,accelerator
```

Create the namespace if it does not exist:

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/00-namespace.yaml
```

The steps that use BusyBox are multi-architecture and do not require a GPU.

## Step 1: create the AI configuration

The first manifest defines non-sensitive model-serving settings:

```bash
cat examples/kubernetes/session-3/1-configmaps/01-configmap.yaml
```

Important values:

```yaml
data:
  MODEL_PROVIDER: "vllm"
  MODEL_NAME: "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
  SERVED_MODEL_NAME: "tinyllama-1b"
  MAX_MODEL_LEN: "1024"
  DTYPE: "half"
  GPU_MEMORY_UTILIZATION: "0.50"
```

Apply it declaratively:

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/1-configmaps/01-configmap.yaml
```

Inspect the independent Kubernetes object:

```bash
kubectl get configmap app-config \
  --namespace session-3

kubectl describe configmap app-config \
  --namespace session-3

kubectl get configmap app-config \
  --namespace session-3 \
  --output yaml
```

The equivalent imperative shape can be previewed without changing the live
object:

```bash
kubectl create configmap app-config \
  --namespace session-3 \
  --from-literal=MODEL_PROVIDER=vllm \
  --from-literal=MODEL_NAME=TinyLlama/TinyLlama-1.1B-Chat-v1.0 \
  --dry-run=client \
  --output yaml
```

Presenter message:

> The ConfigMap exists before a Pod consumes it. It stores small,
> non-sensitive runtime configuration; it does not run the model.

## Step 2: consume every key with envFrom

`02-envfrom.yaml` creates a small AI Model Serving Console. It imports every
key from `app-config`:

```yaml
envFrom:
  - configMapRef:
      name: app-config
```

Deploy it:

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/1-configmaps/02-envfrom.yaml

kubectl rollout status deployment/ai-config-dashboard \
  --namespace session-3
```

Verify the values inside the container:

```bash
kubectl exec \
  --namespace session-3 \
  deployment/ai-config-dashboard -- \
  printenv MODEL_PROVIDER MODEL_NAME SERVED_MODEL_NAME MAX_MODEL_LEN DTYPE
```

Open the dashboard:

```bash
kubectl port-forward \
  --namespace session-3 \
  service/ai-config-dashboard \
  8081:8080
```

Open `http://127.0.0.1:8081` in a browser. The page is still a lightweight
BusyBox application; it visualizes configuration and does not run inference.

Presenter message:

> `envFrom` is concise when a container needs the complete ConfigMap, but it
> also couples the container to every valid key in that object.

## Step 3: consume one selected key

`03-single-key.yaml` creates a preflight Pod that receives only `MODEL_NAME`:

```yaml
env:
  - name: SELECTED_MODEL
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: MODEL_NAME
```

Apply and wait for it:

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/1-configmaps/03-single-key.yaml

kubectl wait pod/model-selection-demo \
  --namespace session-3 \
  --for=condition=Ready \
  --timeout=90s
```

Read the startup message:

```bash
kubectl logs \
  --namespace session-3 \
  model-selection-demo
```

Expected output:

```text
AI model selected through configMapKeyRef: TinyLlama/TinyLlama-1.1B-Chat-v1.0
```

Inspect the reference and the value received by the running container:

```bash
kubectl describe pod model-selection-demo \
  --namespace session-3

kubectl exec \
  --namespace session-3 \
  model-selection-demo -- \
  printenv SELECTED_MODEL
```

Presenter message:

> `configMapKeyRef` documents a precise dependency. This component needs the
> selected model, not every serving parameter.

## Step 4: create a ConfigMap from a file

Many applications expect a file instead of environment variables. Inspect the
ordinary application file:

```bash
cat examples/kubernetes/session-3/1-configmaps/vllm-config.yaml
```

It contains native vLLM server arguments:

```yaml
model: TinyLlama/TinyLlama-1.1B-Chat-v1.0
served-model-name: tinyllama-1b
host: "0.0.0.0"
port: 8000
dtype: half
max-model-len: 1024
gpu-memory-utilization: 0.50
download-dir: /models
```

Preview the imperative conversion from file to ConfigMap:

```bash
kubectl create configmap model-file-config \
  --namespace session-3 \
  --from-file=examples/kubernetes/session-3/1-configmaps/vllm-config.yaml \
  --dry-run=client \
  --output yaml
```

For the repeatable lab, apply the equivalent declarative manifest:

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/1-configmaps/04-file-configmap.yaml

kubectl describe configmap model-file-config \
  --namespace session-3
```

The ConfigMap has one key named `vllm-config.yaml`; the value is the complete
file content.

Presenter message:

> `--from-file` uses the filename as a ConfigMap key. Mounting that ConfigMap
> later recreates the key as a file inside the container.

## Step 5: mount the file and run TinyLlama

This is the only GPU-dependent step. `05-volume.yaml`:

- mounts `model-file-config` at `/etc/model-config`;
- passes the mounted YAML to vLLM through its native `--config` option;
- starts `TinyLlama/TinyLlama-1.1B-Chat-v1.0` with vLLM;
- requests one NVIDIA GPU;
- exposes an OpenAI-compatible API through a ClusterIP Service;
- uses disk-backed `emptyDir` for the downloaded Hugging Face model cache;
- provides memory-backed `/dev/shm` for PyTorch and vLLM workers.

The model is public and does not require an Hugging Face token.

### 5.1 Verify the L40S worker

The fixed worker must be `Ready` with these labels:

```bash
kubectl get nodes \
  --label-columns workload,accelerator
```

Expected GPU labels:

```text
WORKLOAD             ACCELERATOR
gpu-fixed-hi-mem     nvidia-l40s
```

Confirm that Kubernetes advertises the GPU resource:

```bash
kubectl get nodes \
  --selector workload=gpu-fixed-hi-mem \
  --output jsonpath='{range .items[*]}{.metadata.name}{" nvidia.com/gpu="}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'
```

The value must be `1`. If it is empty, install NVIDIA Device Plugin before
applying the model Deployment:

```bash
cd infrastructure/lv-3-cluster-services/nvidia-device-plugin
terraform init
terraform plan
terraform apply
cd ../../..

kubectl rollout status daemonset/nvidia-device-plugin \
  --namespace kube-system \
  --timeout=5m
```

Then run the allocatable-resource command again and confirm
`nvidia.com/gpu=1`.

### 5.2 Deploy vLLM

```bash
kubectl apply \
  --filename examples/kubernetes/session-3/1-configmaps/05-volume.yaml

kubectl get pods \
  --namespace session-3 \
  --watch
```

Stop the watch with `Ctrl+C` after the Pod is `Running`, then wait for vLLM to
download and load TinyLlama:

```bash
kubectl rollout status deployment/tinyllama-vllm \
  --namespace session-3 \
  --timeout=15m

kubectl logs \
  --namespace session-3 \
  deployment/tinyllama-vllm \
  --follow
```

### 5.3 Inspect the mounted configuration

```bash
kubectl exec \
  --namespace session-3 \
  deployment/tinyllama-vllm -- \
  cat /etc/model-config/vllm-config.yaml
```

The file is projected from the ConfigMap and mounted read-only. The model
weights are downloaded separately into `emptyDir`; they are not stored in the
ConfigMap.

### 5.4 Call the model

Forward the Service in one terminal:

```bash
kubectl port-forward \
  --namespace session-3 \
  service/tinyllama-vllm \
  8000:8000
```

Health and model discovery:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/v1/models
```

Send an OpenAI-compatible chat request:

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  --header 'Content-Type: application/json' \
  --data '{
    "model": "tinyllama-1b",
    "messages": [
      {
        "role": "user",
        "content": "Explain Kubernetes ConfigMaps in one short sentence."
      }
    ],
    "max_tokens": 80,
    "temperature": 0.2
  }'
```

## Update behavior

Environment variables are copied when the container starts. Updating
`app-config` does not change an existing container environment:

```bash
kubectl patch configmap app-config \
  --namespace session-3 \
  --type merge \
  --patch '{"data":{"APP_MODE":"updated"}}'

kubectl exec \
  --namespace session-3 \
  deployment/ai-config-dashboard -- \
  printenv APP_MODE
```

Restart the Deployment to receive the new environment value:

```bash
kubectl rollout restart deployment/ai-config-dashboard \
  --namespace session-3
```

ConfigMap volume files update eventually, but vLLM reads
`vllm-config.yaml` only when its process starts. Changing the file does not
reconfigure the running model automatically; restart the Deployment after a
planned configuration update.

Important exception: a ConfigMap volume mounted with `subPath` does not receive
automatic file updates.

## Troubleshooting

### The preflight Pod reports CreateContainerConfigError

Verify that `app-config` exists in the same namespace and contains
`MODEL_NAME`:

```bash
kubectl get configmap app-config \
  --namespace session-3 \
  --output yaml
```

### The vLLM Pod remains Pending

```bash
kubectl describe pod \
  --namespace session-3 \
  --selector app=tinyllama-vllm
```

Common causes are:

- no node with `workload=gpu-fixed-hi-mem`;
- the L40S node group still has desired size zero;
- AWS has insufficient `g6e.xlarge` capacity;
- NVIDIA Device Plugin is missing;
- `nvidia.com/gpu` is not allocatable.

### The vLLM container does not become Ready

```bash
kubectl logs \
  --namespace session-3 \
  deployment/tinyllama-vllm
```

The first startup includes image pulling and downloading model weights. Check
the logs before increasing probe timeouts.

## Cleanup

Delete the GPU workload first:

```bash
kubectl delete \
  --filename examples/kubernetes/session-3/1-configmaps/05-volume.yaml
```

Delete the ConfigMap lab resources:

```bash
kubectl delete \
  --filename examples/kubernetes/session-3/1-configmaps/04-file-configmap.yaml \
  --filename examples/kubernetes/session-3/1-configmaps/03-single-key.yaml \
  --filename examples/kubernetes/session-3/1-configmaps/02-envfrom.yaml \
  --filename examples/kubernetes/session-3/1-configmaps/01-configmap.yaml
```

Turn off the fixed L40S worker after the demonstration:

```bash
aws eks update-nodegroup-config \
  --region us-east-1 \
  --cluster-name 352-demo-dev-eks \
  --nodegroup-name gpu_fixed_l40s-20260806040341667300000001 \
  --scaling-config minSize=0,maxSize=1,desiredSize=0
```

Confirm the safe state:

```bash
aws eks describe-nodegroup \
  --region us-east-1 \
  --cluster-name 352-demo-dev-eks \
  --nodegroup-name gpu_fixed_l40s-20260806040341667300000001 \
  --query 'nodegroup.scalingConfig'
```

Expected values:

```text
minSize: 0
desiredSize: 0
maxSize: 1
```

## Presenter summary

> A ConfigMap separates non-sensitive runtime settings from the container
> image. `envFrom` imports all keys, `configMapKeyRef` selects one key, and a
> ConfigMap volume projects configuration as files. In this lab, the same
> progression ends by using a mounted file to configure a real TinyLlama vLLM
> server. The ConfigMap stores settings; `emptyDir` stores the downloaded model
> temporarily; the L40S executes inference.

## References

- [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [vLLM server configuration file](https://docs.vllm.ai/en/latest/configuration/serve_args/)
- [Official vLLM Docker image](https://docs.vllm.ai/en/latest/deployment/docker/)
