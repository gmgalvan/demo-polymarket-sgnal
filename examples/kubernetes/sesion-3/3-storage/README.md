# Storage in Kubernetes: volumes, PV, PVC, CSI and EFS

This lab follows the storage story end to end, from a directory that dies with
the Pod to a shared filesystem that serves model weights to a GPU node and an
ARM node at the same time.

```text
01 emptyDir            volume tied to the Pod
        |
02 hostPath            volume tied to the node
        |
03 PVC + no driver     Pending: Kubernetes cannot create a disk by itself  -> CSI
        |
   install aws-ebs-csi-driver
        |
04 StorageClass        the catalogue of storage the cluster offers
        |
05 PVC + vLLM (EBS)    the model cache survives the Pod (ReadWriteOnce)
        |
06 PV + PVC estático   binding rules and reclaim policy
        |
   install EFS (Terraform)
        |
07 StorageClass EFS    same interface, different driver
        |
08 PVC RWX + Job       ARM node writes TinyLlama to the shared store
        |
09 vLLM (GPU) + reader GPU serves from EFS while ARM reads the same volume
```

## Learning objectives

- Explain what a volume is and whose lifecycle it follows.
- Tell `emptyDir`, `hostPath`, PersistentVolume and PersistentVolumeClaim apart.
- Describe why Kubernetes needs CSI, and see a PVC fail without a driver.
- Read a StorageClass and know what dynamic provisioning does.
- Apply the binding rules: capacity, access modes, volume mode, storage class.
- Choose between `Retain` and `Delete` reclaim policies.
- Compare `ReadWriteOnce` (EBS) with `ReadWriteMany` (EFS) using a real model.
- Explain why model weights belong on shared storage, not inside the image.

## Prerequisites

Run every command from the repository root and confirm the cluster first:

```bash
cd ~/demo-polymarket-sgnal
kubectl config current-context
```

The output must be exactly:

```text
352-demo-dev-eks
```

Create the namespace if it does not exist:

```bash
kubectl apply \
  --filename examples/kubernetes/sesion-3/00-namespace.yaml
```

Check the workers. Steps 1, 2, 3, 6 and 8 run on the ARM `core` node; steps 5
and 9 need the NVIDIA L40S worker:

```bash
kubectl get nodes \
  --output wide \
  --label-columns workload,accelerator
```

> **Only one GPU is available.** Do not run step 5 and step 9 at the same time:
> the second Pod stays `Pending` waiting for `nvidia.com/gpu`. Delete the
> previous Deployment before starting the next one.

To turn the L40S worker on and off, follow the node group commands in
[`../README.md`](../README.md) (`gpu_fixed_l40s-...`, safe state
`desiredSize: 0`).

---

## Step 0: the interfaces of Kubernetes

Kubernetes does not implement runtimes, networking or storage. It defines three
interfaces and delegates:

```text
CRI  container runtime   containerd, CRI-O
CNI  networking          VPC CNI, Calico, Cilium
CSI  storage             ebs.csi.aws.com, efs.csi.aws.com, Portworx, ...
```

Show the drivers the cluster actually has:

```bash
kubectl get csidriver
kubectl get storageclass
```

Right now there is a single StorageClass (`gp2`) and no EBS driver behind it.
That gap is the subject of step 3.

Presenter message:

> A CSI driver is a program that implements a gRPC contract: `CreateVolume`,
> `DeleteVolume`, `ControllerPublishVolume`. Kubernetes never talks to AWS,
> Dell EMC or Portworx directly; it calls those RPCs and the vendor's driver
> does the work.

---

## Step 1: emptyDir, a volume that belongs to the Pod

```bash
kubectl apply \
  --filename examples/kubernetes/sesion-3/3-storage/01-emptydir.yaml

kubectl wait pod/random-number-generator \
  --namespace sesion-3 \
  --for=condition=Ready \
  --timeout=90s
```

The `generator` container writes a random number every five seconds. Read the
file from the *other* container to prove the volume is shared inside the Pod:

```bash
kubectl exec \
  --namespace sesion-3 \
  random-number-generator \
  --container reader -- \
  cat /opt/number.out
```

A container restart keeps the data, because the volume belongs to the Pod. The
generator exits when a sentinel file appears, and the *reader* container creates
it — which is itself proof that both containers share the volume:

```bash
kubectl exec --namespace sesion-3 random-number-generator \
  --container reader -- touch /opt/restart-me

kubectl get pod random-number-generator --namespace sesion-3
```

> `kubectl exec ... -- kill 1` does **not** work here, and it is worth knowing
> why: the kernel discards signals sent to PID 1 of a namespace unless that
> process installed a handler for them. A plain `/bin/sh` does not, so the
> signal disappears silently and the container never restarts.

`RESTARTS` increases and the file is still there:

```bash
kubectl exec \
  --namespace sesion-3 \
  random-number-generator \
  --container reader -- \
  wc -l /opt/number.out
```

Now delete the Pod and recreate it. The counter starts from zero:

```bash
kubectl delete pod random-number-generator --namespace sesion-3

kubectl apply \
  --filename examples/kubernetes/sesion-3/3-storage/01-emptydir.yaml

sleep 15

kubectl exec \
  --namespace sesion-3 \
  random-number-generator \
  --container reader -- \
  cat /opt/number.out
```

Presenter message:

> `emptyDir` is scratch space: caches, temporary files, a channel between
> containers of one Pod. Never application state.

Clean it up before moving on:

```bash
kubectl delete \
  --filename examples/kubernetes/sesion-3/3-storage/01-emptydir.yaml
```

---

## Step 2: hostPath, a volume that belongs to the node

```bash
kubectl apply \
  --filename examples/kubernetes/sesion-3/3-storage/02-hostpath.yaml

kubectl wait pod/hostpath-number-generator \
  --namespace sesion-3 \
  --for=condition=Ready \
  --timeout=90s

kubectl exec \
  --namespace sesion-3 \
  hostpath-number-generator -- \
  cat /opt/number.out
```

Delete the Pod, recreate it and read again. This time the previous numbers are
still there, because `/data-sesion-3` lives on the node:

```bash
kubectl delete pod hostpath-number-generator --namespace sesion-3

kubectl apply \
  --filename examples/kubernetes/sesion-3/3-storage/02-hostpath.yaml

sleep 15

kubectl exec \
  --namespace sesion-3 \
  hostpath-number-generator -- \
  grep started /opt/number.out
```

Two `started at` lines with **different timestamps**: two Pods wrote to the same
directory. The Pod name is identical because this is a bare Pod, not a
Deployment — the timestamps are what tell the two lives apart.

> Between rehearsals, wipe `/data-sesion-3` on the node or the file keeps
> growing across runs. The cleanup section at the end of this README does it.

Presenter message:

> `hostPath` couples a Pod to a specific node, does not follow rescheduling and
> can expose host files to the container. It is correct for node agents such as
> a log collector or a device plugin, and wrong for application data. The Pod in
> this example is pinned with `nodeSelector` precisely because the data cannot
> travel.

```bash
kubectl delete \
  --filename examples/kubernetes/sesion-3/3-storage/02-hostpath.yaml
```

---

## Step 3: a PVC without a CSI driver

This is the step that explains CSI. Apply the claim and the Pod that consumes
it:

```bash
kubectl apply \
  --filename examples/kubernetes/sesion-3/3-storage/03-pvc-dinamico.yaml

kubectl get pvc,pod --namespace sesion-3
```

Both stay `Pending`. Look at the reason:

```bash
kubectl describe pvc signal-history --namespace sesion-3
```

Expected events:

```text
Normal  WaitForFirstConsumer   waiting for first consumer to be created before binding
Normal  ExternalProvisioning   Waiting for a volume to be created either by the external
                               provisioner 'ebs.csi.aws.com' or manually by the system
                               administrator.
```

Kubernetes already knows *who* should create the volume — the annotation
`volume.kubernetes.io/storage-provisioner: ebs.csi.aws.com` is on the object —
but nobody is listening:

```bash
kubectl get pvc signal-history \
  --namespace sesion-3 \
  --output jsonpath='{.metadata.annotations.volume\.kubernetes\.io/storage-provisioner}{"\n"}'

kubectl get csidriver
kubectl get pods --namespace kube-system | grep -i ebs
```

The annotation prints `ebs.csi.aws.com` even though the StorageClass says
`kubernetes.io/aws-ebs`: that legacy in-tree name is translated to the CSI
driver automatically (CSI migration). And the `grep` returns nothing, because
the driver is not there.

### 3.1 Install the EBS CSI driver

The driver runs in the cluster but creates volumes in AWS, so it needs an IAM
role. Set the variables once:

```bash
export CLUSTER=352-demo-dev-eks
export REGION=us-east-1
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export OIDC=$(aws eks describe-cluster \
  --name "$CLUSTER" \
  --region "$REGION" \
  --query 'cluster.identity.oidc.issuer' \
  --output text | sed 's|https://||')

echo "$ACCOUNT_ID"
echo "$OIDC"
```

Create the trust policy for the driver's service account:

```bash
cat > /tmp/ebs-csi-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC}:aud": "sts.amazonaws.com",
          "${OIDC}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name AmazonEKS_EBS_CSI_DriverRole_352_demo_dev \
  --assume-role-policy-document file:///tmp/ebs-csi-trust.json

aws iam attach-role-policy \
  --role-name AmazonEKS_EBS_CSI_DriverRole_352_demo_dev \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
```

Install the managed add-on:

```bash
aws eks create-addon \
  --cluster-name "$CLUSTER" \
  --region "$REGION" \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn \
    "arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole_352_demo_dev"

aws eks wait addon-active \
  --cluster-name "$CLUSTER" \
  --region "$REGION" \
  --addon-name aws-ebs-csi-driver
```

Verify the driver registered itself:

```bash
kubectl get csidriver
kubectl get pods --namespace kube-system --selector app.kubernetes.io/name=aws-ebs-csi-driver
```

> This lab installs the add-on from the CLI so the audience sees the moment the
> driver appears. For permanent infrastructure, move it to a Terraform stack
> next to `infrastructure/lv-3-cluster-services/`, the same way EFS is managed.

### 3.2 Watch the PVC bind by itself

Nothing needs to be re-applied. The provisioner picks up the pending claim:

```bash
kubectl get pvc,pod --namespace sesion-3 --watch
```

Stop with `Ctrl+C` once the PVC is `Bound` and the Pod is `Running`, then look
at the PersistentVolume Kubernetes created for you:

```bash
kubectl get pv
kubectl describe pv $(kubectl get pvc signal-history \
  --namespace sesion-3 \
  --output jsonpath='{.spec.volumeName}')
```

Prove the data survives the Pod:

```bash
kubectl exec --namespace sesion-3 deployment/signal-writer -- \
  cat /data/history.txt

kubectl delete pod --namespace sesion-3 --selector app=signal-writer

kubectl rollout status deployment/signal-writer --namespace sesion-3

kubectl exec --namespace sesion-3 deployment/signal-writer -- \
  cat /data/history.txt
```

Two lines, two Pods, one EBS volume.

Presenter message:

> The Pod does not name a disk. It names a claim. The claim names a class. The
> class names a driver. That indirection is what lets the same manifest run on
> EBS, on EFS, or on a laptop.

---

## Step 4: an explicit StorageClass

`gp2` is the class EKS ships. In practice you declare your own:

```bash
cat examples/kubernetes/sesion-3/3-storage/04-storageclass-ebs.yaml

kubectl apply \
  --filename examples/kubernetes/sesion-3/3-storage/04-storageclass-ebs.yaml

kubectl get storageclass
```

Points to make while the file is on screen:

- `provisioner` is the CSI driver that will receive `CreateVolume`.
- `parameters` are vendor specific: `type: gp3`, `encrypted: "true"`.
- `reclaimPolicy: Delete` removes the AWS volume with the claim.
- `volumeBindingMode: WaitForFirstConsumer` delays creation until the Pod is
  scheduled, so the EBS volume is born in the right Availability Zone.
- A StorageClass has no namespace.

---

## Step 5: the model cache on EBS

Now the storage lesson meets the AI workload. Confirm the GPU is allocatable:

```bash
kubectl get nodes \
  --selector workload=gpu-fixed-hi-mem \
  --output jsonpath='{range .items[*]}{.metadata.name}{" nvidia.com/gpu="}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}'
```

The value must be `1`. Then deploy:

```bash
kubectl apply \
  --filename examples/kubernetes/sesion-3/3-storage/05-pvc-ebs-vllm.yaml

kubectl get pvc model-cache-ebs --namespace sesion-3

kubectl rollout status deployment/tinyllama-vllm-ebs \
  --namespace sesion-3 \
  --timeout=15m
```

Follow the first start: vLLM downloads TinyLlama into `/models`, which is the
gp3 volume:

```bash
kubectl logs \
  --namespace sesion-3 \
  deployment/tinyllama-vllm-ebs \
  --follow
```

Check the weights landed on the volume and not in the container:

```bash
kubectl exec --namespace sesion-3 deployment/tinyllama-vllm-ebs -- \
  du -sh /models

kubectl exec --namespace sesion-3 deployment/tinyllama-vllm-ebs -- \
  df -h /models
```

Serve a request:

```bash
kubectl port-forward \
  --namespace sesion-3 \
  service/tinyllama-vllm-ebs \
  8000:8000
```

In another terminal:

```bash
curl http://127.0.0.1:8000/v1/models

curl http://127.0.0.1:8000/v1/chat/completions \
  --header 'Content-Type: application/json' \
  --data '{
    "model": "tinyllama-1b",
    "messages": [
      {"role": "user", "content": "What is a PersistentVolumeClaim, in one sentence?"}
    ],
    "max_tokens": 80,
    "temperature": 0.2
  }'
```

### 5.1 The point of the demo: the second start

Delete the Pod and time the restart:

```bash
time kubectl rollout status deployment/tinyllama-vllm-ebs \
  --namespace sesion-3 \
  --timeout=15m
```

*(Run `kubectl delete pod --namespace sesion-3 --selector app=tinyllama-vllm-ebs`
first, in the same breath.)*

There is no download this time. The volume was detached from the old Pod and
attached to the new one with the weights still on it. One line proves it:

```bash
kubectl logs --namespace sesion-3 deployment/tinyllama-vllm-ebs \
  | grep -E "Loading weights took|Application startup complete"
```

Measured on this cluster: first start about 5 minutes, second start **73
seconds**, of which loading the weights from gp3 took **1.36 seconds**.

Presenter message:

> With `emptyDir` (step 1) every restart re-downloads gigabytes while an
> expensive GPU sits idle. A PersistentVolumeClaim turns a cold start into a
> warm one. `ReadWriteOnce` means one node at a time, which is fine for a cache
> but not for a fleet — that limit is what pushes us to EFS.

Free the GPU before step 9:

```bash
kubectl delete \
  --filename examples/kubernetes/sesion-3/3-storage/05-pvc-ebs-vllm.yaml
```

Note that deleting the PVC also deleted the EBS volume, because the class says
`reclaimPolicy: Delete`:

```bash
kubectl get pv
```

---

## Step 6: static provisioning and the binding rules

Not every volume is created on demand. An administrator can publish a
PersistentVolume and let users claim it:

```bash
cat examples/kubernetes/sesion-3/3-storage/06-pv-estatico.yaml

kubectl apply \
  --filename examples/kubernetes/sesion-3/3-storage/06-pv-estatico.yaml

kubectl get pv
kubectl get pvc --namespace sesion-3
```

Expected result:

```text
pv-vol1           1Gi   RWO   Retain   Bound     sesion-3/myclaim   manual
myclaim           Bound     pv-vol1   1Gi   RWO   manual
oversized-claim   Pending                         manual
```

Two lessons in one screen:

- `myclaim` asked for 500Mi and got the whole 1Gi PV. A claim binds to one PV,
  never to a slice of it.
- `oversized-claim` asked for 10Gi. No PV of class `manual` satisfies it, and
  the class has no provisioner, so it waits forever.

The state is the lesson here — Kubernetes emits no event saying "capacity does
not match". What it does say is who is *not* going to help:

```bash
kubectl describe pvc oversized-claim --namespace sesion-3 | tail -5
```

```text
Warning  ProvisioningFailed  no volume plugin matched name: kubernetes.io/no-provisioner
```

That is the point of a `no-provisioner` class: nobody creates volumes
automatically. In static provisioning, if the administrator did not create it,
it does not exist.

The binding rules to state out loud: **sufficient capacity, access modes,
volume mode, storage class** — and, when the PV declares it, node affinity.

Confirm the consumer wrote through the claim:

```bash
kubectl exec --namespace sesion-3 pv-consumer -- cat /data/claim.txt
```

### 6.1 Reclaim policy

Delete the claim and watch what happens to the volume:

```bash
kubectl delete pod pv-consumer --namespace sesion-3
kubectl delete pvc myclaim --namespace sesion-3

kubectl get pv
```

`pv-vol1` moves to `Released`, not `Available`: with `Retain` the data stays and
an administrator must clean it up before the PV can be reused.

| Reclaim policy | What happens when the PVC is deleted |
|---|---|
| `Retain` | PV and data are kept; the PV becomes `Released` and needs manual cleanup |
| `Delete` | The PV and the backing cloud volume are deleted |
| `Recycle` | Deprecated: contents were scrubbed with `rm -rf /scrub/*` |

Clean up:

```bash
kubectl delete pvc oversized-claim --namespace sesion-3 --ignore-not-found
kubectl delete pv pv-vol1 --ignore-not-found
kubectl delete storageclass manual --ignore-not-found
```

---

## Step 7: install EFS

EBS gave us persistence. It cannot give us sharing: one volume, one node, one
Availability Zone. EFS is an NFS filesystem reachable from every node in the
VPC, so it supports `ReadWriteMany`.

The repository already has the Terraform stack. It creates the filesystem, one
mount target per AZ, the security group that allows NFS (2049) from the node
security group, the IRSA role, the EFS CSI driver via Helm and the
`efs-sc` StorageClass.

```bash
cat infrastructure/lv-3-cluster-services/efs/main.tf
```

> **Check this first.** The cluster currently has an orphan `efs.csi.aws.com`
> CSIDriver object that no Helm release owns. Helm refuses to adopt it with
> `invalid ownership metadata`. Remove it before applying:
>
> ```bash
> kubectl get csidriver efs.csi.aws.com
> kubectl get pods --namespace kube-system --selector app.kubernetes.io/name=aws-efs-csi-driver
> # If the object exists but no driver Pods do, it is a leftover:
> kubectl delete csidriver efs.csi.aws.com
> ```

Apply the stack:

```bash
cd infrastructure/lv-3-cluster-services/efs
terraform init
terraform plan
terraform apply
cd ../../..
```

Verify the AWS side:

```bash
aws efs describe-file-systems \
  --region us-east-1 \
  --query 'FileSystems[].{id:FileSystemId,state:LifeCycleState,name:Name}' \
  --output table

FS_ID=$(aws efs describe-file-systems --region us-east-1 \
  --query 'FileSystems[0].FileSystemId' --output text)

aws efs describe-mount-targets \
  --region us-east-1 \
  --file-system-id "$FS_ID" \
  --query 'MountTargets[].{az:AvailabilityZoneName,state:LifeCycleState,ip:IpAddress}' \
  --output table
```

Every AZ that hosts a worker must have a mount target in `available` state.
Compare with:

```bash
kubectl get nodes --label-columns topology.kubernetes.io/zone
```

Verify the Kubernetes side:

```bash
kubectl get csidriver
kubectl get pods --namespace kube-system --selector app.kubernetes.io/name=aws-efs-csi-driver
kubectl get storageclass
```

`efs-sc` must appear with provisioner `efs.csi.aws.com`.

Now read what Terraform produced next to the hand-written equivalent:

```bash
kubectl get storageclass efs-sc --output yaml
cat examples/kubernetes/sesion-3/3-storage/07-efs-storageclass.yaml
```

`07-efs-storageclass.yaml` is a reference copy. **Do not apply it** when
Terraform already created `efs-sc`; it exists so the audience can see the
manifest, and as a fallback if Terraform is not used (replace `fs-REPLACE_ME`
with the real filesystem id).

Applying it anyway fails with a useful error, which is worth showing on purpose
if there is time:

```text
The StorageClass "efs-sc" is invalid: parameters: Forbidden: updates to
parameters are forbidden.
```

A StorageClass is immutable in its `parameters` and `provisioner`. To change a
class you delete it and recreate it — existing PVs keep working, because they
already recorded what they needed at provisioning time.

Key differences with the EBS class:

| | `ebs-sc` | `efs-sc` |
|---|---|---|
| Driver | `ebs.csi.aws.com` | `efs.csi.aws.com` |
| Access modes | `ReadWriteOnce` | `ReadWriteMany` |
| Topology | one Availability Zone | every AZ of the VPC |
| Binding mode | `WaitForFirstConsumer` | `Immediate` |
| Provisioning | a new block device per claim | an Access Point on one filesystem |

---

## Step 8: write the model to the shared store from an ARM node

```bash
kubectl apply \
  --filename examples/kubernetes/sesion-3/3-storage/08-efs-model-store.yaml

kubectl get pvc model-store-efs --namespace sesion-3
```

The claim binds immediately — no Pod required, because EFS has no AZ to choose:

```bash
kubectl get pv
```

Follow the download. It runs on the ARM worker; the GPU is untouched:

```bash
kubectl get pods --namespace sesion-3 --selector job-name=efs-model-downloader --output wide

kubectl logs --namespace sesion-3 job/efs-model-downloader --follow

kubectl wait --for=condition=complete job/efs-model-downloader \
  --namespace sesion-3 \
  --timeout=20m
```

Presenter message:

> Moving 2 GB from Hugging Face is network work, not GPU work. Doing it on a
> `m7g.large` at about USD 0.08 per hour instead of on a GPU node at about USD
> 1.86 per hour is the same idea as running the agent, the gateway and the MCP
> servers on Graviton: only inference belongs on the accelerator.

---

## Step 9: serve from EFS on the GPU, read from ARM at the same time

Make sure step 5 released the GPU:

```bash
kubectl get pods --namespace sesion-3 --output wide
```

Deploy:

```bash
kubectl apply \
  --filename examples/kubernetes/sesion-3/3-storage/09-efs-vllm.yaml

kubectl rollout status deployment/tinyllama-vllm-efs \
  --namespace sesion-3 \
  --timeout=15m
```

The startup log shows no download at all: the weights were already there,
written by a different Pod, on a different node, with a different CPU
architecture.

```bash
kubectl logs --namespace sesion-3 deployment/tinyllama-vllm-efs | head -40
```

Show the two Pods holding the same volume:

```bash
kubectl get pods --namespace sesion-3 --output wide

kubectl logs --namespace sesion-3 efs-reader

kubectl exec --namespace sesion-3 efs-reader -- \
  ls -lh /models/TinyLlama-1.1B-Chat-v1.0
```

The reader runs on `aarch64`, vLLM runs on `x86_64` with an L40S, and both see
the same files. Confirm the mount is read-only for the model server:

```bash
kubectl exec --namespace sesion-3 deployment/tinyllama-vllm-efs -- \
  sh -c 'touch /models/should-fail 2>&1 || echo "-> read-only mount, as declared"'
```

Measured on this cluster: loading the weights from EFS took **4.67 seconds**,
against 1.36 from gp3. EFS pays a network tax on first read and gives back
`ReadWriteMany` — that trade is the whole decision.

Serve a request:

```bash
kubectl port-forward \
  --namespace sesion-3 \
  service/tinyllama-vllm-efs \
  8000:8000
```

```bash
curl http://127.0.0.1:8000/v1/models

curl http://127.0.0.1:8000/v1/chat/completions \
  --header 'Content-Type: application/json' \
  --data '{
    "model": "tinyllama-1b",
    "messages": [
      {"role": "user", "content": "Why is shared storage useful for model serving?"}
    ],
    "max_tokens": 100,
    "temperature": 0.2
  }'
```

Presenter message:

> With `ReadWriteMany` the model is downloaded once and mounted by every
> replica. Scaling from one to ten Pods costs ten GPU allocations, not ten
> downloads. This is the storage half of the multi-architecture story: the ARM
> node prepared the weights, the GPU node runs the inference, and neither
> manifest mentions a disk.

---

## Comparison to close the lesson

| | `emptyDir` | `hostPath` | EBS (`ebs-sc`) | EFS (`efs-sc`) |
|---|---|---|---|---|
| Lifecycle | the Pod | the node | independent | independent |
| Survives Pod deletion | no | yes, same node only | yes | yes |
| Follows rescheduling | n/a | no | yes, within the AZ | yes, any AZ |
| Access modes | — | — | `ReadWriteOnce` | `ReadWriteMany` |
| Shared between Pods | same Pod only | same node only | one node at a time | many nodes |
| Typical AI use | scratch, `/dev/shm` | node agents | per-node model cache | shared model store |

---

## Troubleshooting

### The PVC stays `Pending`

```bash
kubectl describe pvc <name> --namespace sesion-3
```

- `Waiting for a volume to be created ... external provisioner`: the CSI driver
  is missing or not running.
- `waiting for first consumer`: expected with `WaitForFirstConsumer`; it binds
  when a Pod is scheduled.
- `storageclass.storage.k8s.io "x" not found`: the class name is wrong.
- Static PV: no PV matches capacity, access modes or class (step 6).

### The EFS Pod hangs in `ContainerCreating`

```bash
kubectl describe pod <name> --namespace sesion-3
kubectl logs --namespace kube-system --selector app=efs-csi-node --container efs-plugin
```

Usual causes: no mount target in the node's AZ, or the EFS security group does
not allow TCP 2049 from the node security group.

### The GPU Pod stays `Pending`

```bash
kubectl describe pod --namespace sesion-3 --selector app=tinyllama-vllm-efs
```

Usually the other vLLM Deployment still holds the single GPU, the L40S node
group is scaled to zero, or the NVIDIA device plugin is missing.

### `terraform apply` fails on the EFS CSI driver

`invalid ownership metadata` on `CSIDriver efs.csi.aws.com` means the orphan
object from step 7 is still there. Delete it and apply again.

---

## Cleanup

Namespace resources:

```bash
kubectl delete \
  --filename examples/kubernetes/sesion-3/3-storage/09-efs-vllm.yaml \
  --ignore-not-found

kubectl delete \
  --filename examples/kubernetes/sesion-3/3-storage/08-efs-model-store.yaml \
  --ignore-not-found

kubectl delete \
  --filename examples/kubernetes/sesion-3/3-storage/05-pvc-ebs-vllm.yaml \
  --ignore-not-found

kubectl delete \
  --filename examples/kubernetes/sesion-3/3-storage/03-pvc-dinamico.yaml \
  --ignore-not-found

kubectl delete pv pv-vol1 --ignore-not-found
```

Confirm nothing is left holding a volume:

```bash
kubectl get pvc --namespace sesion-3
kubectl get pv
```

`efs-sc` is `Retain`, so its PV survives the claim as `Released` and leaves an
EFS access point behind in AWS. Delete both, or the next rehearsal accumulates
orphans:

```bash
kubectl delete pv --field-selector status.phase=Released --ignore-not-found

aws efs describe-access-points --region us-east-1 \
  --query 'AccessPoints[].{id:AccessPointId,path:RootDirectory.Path}' --output table
# aws efs delete-access-point --region us-east-1 --access-point-id fsap-xxxxxxxx
```

Wipe the two `hostPath` directories on the ARM node so steps 2 and 6 start from
zero next time:

```bash
kubectl run hostpath-cleanup -n sesion-3 --rm -i --restart=Never --image=busybox:1.36 \
  --overrides='{"spec":{"nodeSelector":{"workload":"core"},"containers":[{"name":"c","image":"busybox:1.36","command":["sh","-c","rm -rf /h1/* /h2/*; echo clean"],"volumeMounts":[{"name":"h1","mountPath":"/h1"},{"name":"h2","mountPath":"/h2"}]}],"volumes":[{"name":"h1","hostPath":{"path":"/data-sesion-3","type":"DirectoryOrCreate"}},{"name":"h2","hostPath":{"path":"/mnt/pv-sesion-3","type":"DirectoryOrCreate"}}]}}'
```

Turn the GPU worker off:

```bash
aws eks update-nodegroup-config \
  --region us-east-1 \
  --cluster-name 352-demo-dev-eks \
  --nodegroup-name gpu_fixed_l40s-20260806040341667300000001 \
  --scaling-config minSize=0,maxSize=1,desiredSize=0

aws eks describe-nodegroup \
  --region us-east-1 \
  --cluster-name 352-demo-dev-eks \
  --nodegroup-name gpu_fixed_l40s-20260806040341667300000001 \
  --query 'nodegroup.scalingConfig'
```

EFS keeps charging for stored data. If the demo is over:

```bash
cd infrastructure/lv-3-cluster-services/efs
terraform destroy
cd ../../..
```

> `efs-sc` has `reclaimPolicy: Retain`, so deleting the PVC leaves the PV and
> the access point behind. Delete leftover PVs before destroying the stack, or
> Terraform will remove the filesystem with the data still on it.

The EBS CSI add-on and its IAM role can stay; they cost nothing when idle. To
remove them:

```bash
aws eks delete-addon --cluster-name 352-demo-dev-eks --region us-east-1 \
  --addon-name aws-ebs-csi-driver

aws iam detach-role-policy \
  --role-name AmazonEKS_EBS_CSI_DriverRole_352_demo_dev \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

aws iam delete-role --role-name AmazonEKS_EBS_CSI_DriverRole_352_demo_dev
```

---

## Presenter summary

> A volume is a directory with a lifecycle. `emptyDir` follows the Pod,
> `hostPath` follows the node, and a PersistentVolume follows nobody. Users ask
> for storage with a PersistentVolumeClaim; the StorageClass decides which CSI
> driver serves it; the driver talks to AWS. That indirection is why the same
> vLLM manifest can cache a model on a gp3 disk or share it from EFS across an
> ARM node and a GPU node, without a single line about hardware.

## References

- [Volumes](https://kubernetes.io/docs/concepts/storage/volumes/)
- [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Container Storage Interface specification](https://github.com/container-storage-interface/spec)
- [Amazon EBS CSI driver on EKS](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html)
- [Amazon EFS CSI driver on EKS](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)
- [Model storage strategies in this repository](../../base-deployments/01-model-storage/README.md)
