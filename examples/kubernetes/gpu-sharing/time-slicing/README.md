# GPU Sharing — Time-Slicing on gpu-fixed

This folder documents the **time-slicing configuration** used for the
`gpu-fixed` lane.

The baseline story is:

- one workload requests `nvidia.com/gpu: 1`
- Kubernetes treats the whole GPU as exclusively allocated
- a second workload stays `Pending` with `Insufficient nvidia.com/gpu`

The optimization story is:

- enable **time-slicing** in the NVIDIA device plugin
- advertise multiple logical shares from the same physical GPU
- retry the second workload and show that it can now schedule

## What is in this folder

- [nvidia-device-plugin-timeslicing-config.yaml](./nvidia-device-plugin-timeslicing-config.yaml)

That file is the **YAML representation** of the time-slicing config:

- resource: `nvidia.com/gpu`
- replicas: `4`
- `failRequestsGreaterThanOne: true`

## How to apply it

There are two ways to use this config:

1. **Fast demo path**
- apply the YAML
- run a `helm upgrade` so the live device plugin uses it

2. **Terraform path**
- use the Terraform toggle in the repo
- this is the long-term source of truth

For a live demo, the **fast path** is often more convenient.

## Important note

This is a **demo-oriented sharing mode**, not strong isolation.

- good for showing higher packing density
- not the same as MIG
- pods still contend for the same physical GPU

## Enable time-slicing with YAML + Helm

Apply the ConfigMap first:

```bash
kubectl apply -f examples/kubernetes/gpu-sharing/time-slicing/nvidia-device-plugin-timeslicing-config.yaml
```

Then update the NVIDIA device plugin so it consumes that config:

```bash
helm upgrade --install nvidia-device-plugin nvidia-device-plugin/nvidia-device-plugin \
  -n kube-system \
  --repo https://nvidia.github.io/k8s-device-plugin \
  --set gfd.enabled=false \
  --set-string 'tolerations[0].key=nvidia.com/gpu' \
  --set-string 'tolerations[0].operator=Exists' \
  --set-string 'tolerations[0].effect=NoSchedule' \
  --set-string 'affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=workload' \
  --set-string 'affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=In' \
  --set-string 'affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]=gpu' \
  --set-string 'affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[1]=gpu-nim' \
  --set-string 'affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[2]=gpu-fixed' \
  --set config.name=nvidia-device-plugin-timeslicing \
  --set config.default=default
```

## Enable time-slicing with Terraform

Time-slicing is **off by default**. Turn it on explicitly:

```bash
cd infrastructure/lv-3-cluster-services/nvidia-device-plugin
terraform apply \
  -var='time_slicing_enabled=true' \
  -var='time_slicing_replicas=4'
```

## Validate that the plugin rolled

```bash
kubectl get pods -n kube-system | grep nvidia-device-plugin
kubectl describe node -l workload=gpu-fixed | grep -A8 nvidia.com/gpu
```

After the plugin update settles, the fixed node should advertise more than one
logical GPU share.

## Suggested validation flow

1. Keep one workload already running on `gpu-fixed`
   Example: `llama31-8b-gpu-fixed` on KServe
2. Re-try the workload that previously failed with:

```bash
Insufficient nvidia.com/gpu
```

For example:

```bash
kubectl apply -k examples/kubernetes/nim/llama31-8b-gpu-fixed
```

Watch it:

```bash
kubectl get pods -n demo-examples -w
kubectl get nimcache,nimservice -n demo-examples -w
```

If time-slicing is working, the second workload should no longer stay
`Pending` for lack of GPU.

## Disable time-slicing again with Helm

If you enabled it with the fast `yaml + helm` path, remove the time-slicing
config from the live release like this:

```bash
helm upgrade --install nvidia-device-plugin nvidia-device-plugin/nvidia-device-plugin \
  -n kube-system \
  --repo https://nvidia.github.io/k8s-device-plugin \
  --set gfd.enabled=false \
  --set-string 'tolerations[0].key=nvidia.com/gpu' \
  --set-string 'tolerations[0].operator=Exists' \
  --set-string 'tolerations[0].effect=NoSchedule' \
  --set-string 'affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].key=workload' \
  --set-string 'affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].operator=In' \
  --set-string 'affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[0]=gpu' \
  --set-string 'affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[1]=gpu-nim' \
  --set-string 'affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0].values[2]=gpu-fixed'
```

Optionally remove the ConfigMap too:

```bash
kubectl delete -f examples/kubernetes/gpu-sharing/time-slicing/nvidia-device-plugin-timeslicing-config.yaml
```

## Reconcile with Terraform to avoid drift

If you used the fast `yaml + helm` path, finish by reconciling the release back
to Terraform:

```bash
cd infrastructure/lv-3-cluster-services/nvidia-device-plugin
terraform apply -var='time_slicing_enabled=false'
```

Or, if you want Terraform to keep time-slicing enabled:

```bash
cd infrastructure/lv-3-cluster-services/nvidia-device-plugin
terraform apply \
  -var='time_slicing_enabled=true' \
  -var='time_slicing_replicas=4'
```

## Disable time-slicing again with Terraform

```bash
cd infrastructure/lv-3-cluster-services/nvidia-device-plugin
terraform apply \
  -var='time_slicing_enabled=false'
```
