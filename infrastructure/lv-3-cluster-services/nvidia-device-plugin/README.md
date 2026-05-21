# NVIDIA Device Plugin (lv-3 cluster services)

This stack installs the NVIDIA Kubernetes device plugin for GPU nodes.

It is intentionally separate from:

- `infrastructure/lv-3-cluster-services/karpenter/`
- `infrastructure/lv-3-cluster-services/neuron-device-plugin/`

so GPU runtime plumbing stays distinct from autoscaling and from Inferentia.

## Usage

If `lv-2-core-compute/eks` was just recreated, refresh kubeconfig first:

```bash
aws eks update-kubeconfig --region us-east-1 --name 352-demo-dev-eks
kubectl get nodes
```

Otherwise Helm/Terraform may fail with:

```bash
Kubernetes cluster unreachable: the server has asked for the client to provide credentials
```

```bash
cd infrastructure/lv-3-cluster-services/nvidia-device-plugin
terraform init
terraform plan
terraform apply
```
