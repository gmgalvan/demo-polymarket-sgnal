# NVIDIA Device Plugin (lv-3 cluster services)

This stack installs the NVIDIA Kubernetes device plugin for GPU nodes.

It is intentionally separate from:

- `infrastructure/lv-3-cluster-services/karpenter/`
- `infrastructure/lv-3-cluster-services/neuron-device-plugin/`

so GPU runtime plumbing stays distinct from autoscaling and from Inferentia.

## Usage

```bash
cd infrastructure/lv-3-cluster-services/nvidia-device-plugin
terraform init
terraform plan
terraform apply
```
