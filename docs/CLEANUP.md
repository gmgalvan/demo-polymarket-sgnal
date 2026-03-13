# Full Cleanup Runbook (K8s -> EKS -> VPC -> ECR -> Docker local)

Este runbook borra todo en orden seguro:

1. Workloads de Kubernetes
2. Stack `lv-3` (Karpenter)
3. Stack `lv-2` (EKS)
4. Stack `lv-0` (VPC)
5. Repositorio ECR del ejemplo Neuron
6. Cache/objetos locales de Docker

## Variables base

```bash
export AWS_REGION=us-east-1
export CLUSTER_NAME=352-demo-dev-eks
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## 1) Cleanup de Kubernetes (examples)

```bash
cd /home/gmgalvan/demo-polymarket-signal

kubectl delete -k kubernetes/ex-vllm-qwen25-3b-gpu --ignore-not-found
kubectl delete -k kubernetes/ex-inferentia-smoke-inf2 --ignore-not-found
kubectl delete -k kubernetes/ex-vllm-neuron-llama31-8b-inf2 --ignore-not-found

kubectl delete deployment -n ai-example --all --ignore-not-found
kubectl delete service -n ai-example --all --ignore-not-found
kubectl delete pod -n ai-example --all --force --grace-period=0 --ignore-not-found
kubectl delete namespace ai-example --ignore-not-found
```

Verifica:

```bash
kubectl get pods -A | grep -E 'ai-example|vllm|neuron-smoke' || true
```

## 2) Cleanup Karpenter (lv-3)

```bash
cd /home/gmgalvan/demo-polymarket-signal/infrastructure/lv-3-cluster-services/karpenter
terraform init -upgrade
terraform destroy
```

Si presionaste `Ctrl+C` dos veces y salió `Error: operation canceled`, vuelve a correr `terraform destroy`.
Evita interrumpirlo otra vez mientras libera lock/state.

Si se queda atorado por finalizers (`Timed out when waiting for resource ... to be deleted`), ejecuta:

```bash
kubectl delete nodepool arm-general gpu-inference neuron-inference --ignore-not-found --wait=false
kubectl delete nodeclaim --all --ignore-not-found --wait=false
kubectl patch ec2nodeclass arm-general --type merge -p '{"metadata":{"finalizers":[]}}' || true
kubectl patch ec2nodeclass gpu-inference --type merge -p '{"metadata":{"finalizers":[]}}' || true
kubectl patch ec2nodeclass neuron-inference --type merge -p '{"metadata":{"finalizers":[]}}' || true
kubectl delete ec2nodeclass arm-general gpu-inference neuron-inference --ignore-not-found --wait=false
```

Luego vuelve a correr:

```bash
cd /home/gmgalvan/demo-polymarket-signal/infrastructure/lv-3-cluster-services/karpenter
terraform destroy
```

Si queda atorado específicamente en `module.eks_karpenter.helm_release.karpenter_crd`:

```bash
cd /home/gmgalvan/demo-polymarket-signal/infrastructure/lv-3-cluster-services/karpenter

# borra metadata Helm del release atascado
kubectl delete secret -n kube-system -l owner=helm,name=karpenter-crd --ignore-not-found

# remueve ese recurso del state de lv-3
terraform state rm module.eks_karpenter.helm_release.karpenter_crd

# valida que ya no quede recurso gestionado en lv-3
terraform state list
```

Resultado esperado:
- solo entradas `data.*` (sin `module.eks_karpenter.*` recursos reales)
- después ya puedes continuar con `lv-2` (`terraform destroy`)

Si aparece lock de Terraform:

```bash
terraform force-unlock <LOCK_ID>
```

Verifica:

```bash
kubectl get nodepools
kubectl get nodeclaims
kubectl get ec2nodeclasses
```

## 3) Cleanup EKS (lv-2)

```bash
cd /home/gmgalvan/demo-polymarket-signal/infrastructure/lv-2-core-compute/eks
terraform init -upgrade
terraform destroy
```

## 4) Cleanup VPC (lv-0)

```bash
cd /home/gmgalvan/demo-polymarket-signal/infrastructure/lv-0-networking/vpc
terraform init -upgrade
terraform destroy
```

## 5) Cleanup ECR (imagen Neuron de ejemplo)

Si creaste el repo `vllm-neuron` para el ejemplo:

```bash
aws ecr describe-repositories --repository-names vllm-neuron --region "${AWS_REGION}"
aws ecr delete-repository --repository-name vllm-neuron --region "${AWS_REGION}" --force
```

## 6) Cleanup Docker local (WSL/Docker Desktop)

Comandos agresivos (borran cache/images/containers/volumes no usados):

```bash
docker ps -aq | xargs -r docker stop
docker system prune -a --volumes -f
docker builder prune -a -f
docker buildx prune -a -f
docker system df
```

## Opcional: liberar espacio en WSL2 (desde PowerShell como admin)

```powershell
wsl --shutdown
```

## Orden recomendado de ejecución (resumen corto)

```bash
# 1) Kubernetes examples
# 2) terraform destroy en lv-3
# 3) terraform destroy en lv-2
# 4) terraform destroy en lv-0
# 5) borrar ECR de ejemplos
# 6) docker prune local
```
