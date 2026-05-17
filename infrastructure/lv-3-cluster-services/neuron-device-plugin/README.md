# AWS Neuron Device Plugin (lv-3 cluster services)

This stack installs the AWS Neuron Kubernetes device plugin for Inferentia
nodes.

It is intentionally separate from:

- `infrastructure/lv-3-cluster-services/karpenter/`
- `infrastructure/lv-3-cluster-services/nvidia-device-plugin/`

so Inferentia runtime plumbing stays distinct from autoscaling and from GPU.

## Usage

```bash
cd infrastructure/lv-3-cluster-services/neuron-device-plugin
terraform init
terraform plan
terraform apply
```
