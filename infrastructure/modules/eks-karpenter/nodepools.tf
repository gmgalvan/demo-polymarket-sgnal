# ── EC2NodeClass ──────────────────────────────────────────────────────────────
#
# EC2NodeClass defines the "instance template" Karpenter uses when launching
# EC2 nodes. It specifies: which AMI to use, which subnets/security groups to
# launch into, the node IAM instance profile, and the root disk size.
#
# Each class maps to a different hardware type:
#   arm-general      → Graviton (ARM64)  — lightweight services, low cost
#   gpu-inference    → NVIDIA GPU        — CUDA-based inference
#   neuron-inference → AWS Inferentia2   — Neuron SDK inference (inf2)
#
# The NodePool references an EC2NodeClass and adds scheduling constraints
# (taints, labels, instance type) so pods land on the right hardware automatically.

# ─── EC2NodeClass: ARM / Graviton ────────────────────────────────────────────
# Template for ARM64 (Graviton) nodes. Used for lightweight workloads:
# LiteLLM gateway, MCP servers, the Strands agent process, observability.
# 40Gi disk — enough for application containers without large model weights.
resource "kubectl_manifest" "ec2_node_class_arm" {
  count = var.enable_karpenter_nodepools ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "arm-general"
    }
    spec = {
      # AL2023 = Amazon Linux 2023. Karpenter resolves the exact AMI ID
      # from the SSM parameter (see locals.tf → arm_ami_ssm_parameter).
      amiFamily = "AL2023"
      amiSelectorTerms = [
        {
          ssmParameter = local.arm_ami_ssm_parameter
        }
      ]
      # IAM instance profile inherited by EC2 nodes. Required for the kubelet
      # to call the EKS API and for ECR/SSM access.
      instanceProfile = var.karpenter_instance_profile_name
      # Karpenter launches nodes into the VPC private subnets.
      subnetSelectorTerms = [
        for subnet_id in var.private_subnet_ids : {
          id = subnet_id
        }
      ]
      # Two security groups: the EKS cluster SG (control-plane ↔ node)
      # and the additional node SG (pod-to-pod network rules).
      securityGroupSelectorTerms = [
        {
          id = var.cluster_primary_security_group_id
        },
        {
          id = var.node_security_group_id
        }
      ]
      # Root disk: 40Gi gp3, encrypted, deleted when the instance terminates.
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "40Gi"
            volumeType          = "gp3"
            deleteOnTermination = true
            encrypted           = true
          }
        }
      ]
    }
  })

  # EC2NodeClass uses Karpenter CRDs — the Helm release must exist first.
  depends_on = [helm_release.karpenter]
}

# ─── EC2NodeClass: GPU (NVIDIA) ───────────────────────────────────────────────
# Template for NVIDIA GPU nodes (g5/g6 instances, e.g. g6.xlarge with L40S).
# The AMI includes CUDA drivers and the NVIDIA device plugin via AL2023.
# 200Gi disk — large LLM models (30B-70B) can weigh 60-140 GB.
resource "kubectl_manifest" "ec2_node_class_gpu" {
  count = var.enable_karpenter_nodepools ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "gpu-inference"
    }
    spec = {
      # SSM parameter points to the EKS-optimized AMI with GPU (CUDA) support.
      amiFamily = "AL2023"
      amiSelectorTerms = [
        {
          ssmParameter = local.gpu_ami_ssm_parameter
        }
      ]
      instanceProfile = var.karpenter_instance_profile_name
      subnetSelectorTerms = [
        for subnet_id in var.private_subnet_ids : {
          id = subnet_id
        }
      ]
      securityGroupSelectorTerms = [
        {
          id = var.cluster_primary_security_group_id
        },
        {
          id = var.node_security_group_id
        }
      ]
      # 200Gi to hold the vLLM container image plus model weights on disk.
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "200Gi"
            volumeType          = "gp3"
            deleteOnTermination = true
            encrypted           = true
          }
        }
      ]
    }
  })

  depends_on = [helm_release.karpenter]
}

# ─── EC2NodeClass: Inferentia2 (AWS Neuron) ───────────────────────────────────
# Template for AWS Inferentia2 nodes (inf2.xlarge, inf2.8xlarge, etc.).
# The AMI includes the Neuron SDK (neuronx-tools, aws-neuronx-dkms) so the
# device plugin can expose NeuronCores as Kubernetes resources
# (aws.amazon.com/neuroncore). Models must be pre-compiled with optimum-neuron.
# 150Gi disk — Neuron-compiled model artifacts (.neff files) can be large.
resource "kubectl_manifest" "ec2_node_class_inferentia" {
  count = var.enable_karpenter_nodepools ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "neuron-inference"
    }
    spec = {
      # SSM parameter points to the EKS-optimized AMI with Neuron support (inf2).
      # Example path: /aws/service/eks/optimized-ami/.../x86_64/neuron/recommended/image_id
      amiFamily = "AL2023"
      amiSelectorTerms = [
        {
          ssmParameter = local.inf_ami_ssm_parameter
        }
      ]
      instanceProfile = var.karpenter_instance_profile_name
      subnetSelectorTerms = [
        for subnet_id in var.private_subnet_ids : {
          id = subnet_id
        }
      ]
      securityGroupSelectorTerms = [
        {
          id = var.cluster_primary_security_group_id
        },
        {
          id = var.node_security_group_id
        }
      ]
      # 150Gi to hold the vLLM-Neuron image and compiled model artifacts (.neff).
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "150Gi"
            volumeType          = "gp3"
            deleteOnTermination = true
            encrypted           = true
          }
        }
      ]
    }
  })

  depends_on = [helm_release.karpenter]
}

# ── NodePool ─────────────────────────────────────────────────────────────────
#
# NodePool defines the scheduling rules Karpenter uses to decide WHEN and
# WHERE to launch pods. It references an EC2NodeClass and adds:
#   - Labels:       allow pods to target a pool via nodeSelector
#   - Taints:       prevent pods without a toleration from landing on expensive nodes
#   - Requirements: restrict instance type, architecture, and capacity type
#   - Disruption:   consolidation policy to terminate idle nodes and save cost
#
# Flow: Pending pod → Karpenter evaluates NodePools → launches EC2 per EC2NodeClass
#       → kubelet registers → pod schedules → device plugin exposes resources.

# ─── NodePool: ARM / Graviton ─────────────────────────────────────────────────
# Nodes for all workloads that do NOT need an accelerator:
# LiteLLM, MCP servers, Strands agent, EventBridge forwarder, Grafana, LangFuse.
# No taint — pods without a nodeSelector can also land here (default pool).
# consolidateAfter=5m: released quickly since they are cheap and usage is variable.
resource "kubectl_manifest" "node_pool_arm" {
  count = var.enable_karpenter_nodepools ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "arm-general"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            # Pods use nodeSelector: workload=core to target this pool.
            workload = "core"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "arm-general"
          }
          requirements = [
            {
              # ARM64 only (Graviton: m7g, c7g, t4g, etc.)
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["arm64"]
            },
            {
              # Exact instance type — configurable via variable (e.g. m7g.large)
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = [var.core_node_instance_type]
            },
            {
              # on-demand: guaranteed availability for critical services
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            }
          ]
        }
      }
      disruption = {
        # Consolidate when the node is empty OR underutilized (bin-packing)
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        # Wait 5 min before terminating an underutilized node to avoid flapping
        consolidateAfter    = "5m"
      }
    }
  })

  depends_on = [kubectl_manifest.ec2_node_class_arm]
}

# ─── NodePool: GPU (NVIDIA) ───────────────────────────────────────────────────
# Nodes for NVIDIA GPU inference. Karpenter launches them only when a pod
# tolerates the nvidia.com/gpu:NoSchedule taint and requests nvidia.com/gpu.
# In this demo: vLLM pods running Qwen3-30B or Llama3.1-70B models.
# consolidateAfter=10m: GPU instances are expensive (~$1-4/hr) — consolidated
# faster than ARM but with enough buffer to avoid frequent cold-starts.
resource "kubectl_manifest" "node_pool_gpu" {
  count = var.enable_karpenter_nodepools ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "gpu-inference"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            accelerator = "nvidia-l40s" # Descriptive label for the accelerator type
            workload    = "gpu"         # nodeSelector: workload=gpu in vLLM pods
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "gpu-inference"
          }
          taints = [
            {
              # Guard taint: only pods with a nvidia.com/gpu toleration can
              # schedule here. Prevents lightweight services from consuming
              # expensive GPU nodes.
              key    = "nvidia.com/gpu"
              value  = "true"
              effect = "NoSchedule"
            }
          ]
          requirements = [
            {
              # GPU nodes are x86_64 (amd64)
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              # GPU instance type — e.g. g6.xlarge (L40S), g5.xlarge (A10G)
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = [var.l40s_instance_type]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            }
          ]
        }
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "10m"
      }
    }
  })

  depends_on = [kubectl_manifest.ec2_node_class_gpu]
}

# ─── NodePool: Inferentia2 (AWS Neuron) ───────────────────────────────────────
# Nodes for AWS Inferentia2 inference. Karpenter launches them only when a pod
# tolerates aws.amazon.com/neuron:NoSchedule and requests aws.amazon.com/neuroncore.
# In this demo: vLLM pods running Neuron-compiled models (TinyLlama, Llama3.1-8B).
#
# The Neuron device plugin (installed by helm_release.neuron_device_plugin in main.tf)
# runs as a DaemonSet on these nodes and exposes NeuronCores as allocatable
# resources — without it, pods cannot request aws.amazon.com/neuroncore.
#
# ~40-70% cheaper than equivalent GPU for compatible models.
resource "kubectl_manifest" "node_pool_inferentia" {
  count = var.enable_karpenter_nodepools ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "neuron-inference"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            accelerator = "aws-inferentia2" # Descriptive label for the accelerator type
            workload    = "neuron"          # nodeSelector: workload=neuron in vLLM pods
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "neuron-inference"
          }
          taints = [
            {
              # Guard taint: only pods with an aws.amazon.com/neuron toleration
              # can schedule here. Prevents non-Neuron workloads from landing
              # on inf2 instances.
              key    = "aws.amazon.com/neuron"
              value  = "true"
              effect = "NoSchedule"
            }
          ]
          requirements = [
            {
              # Inferentia2 is x86_64 (amd64), not ARM
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              # Inferentia instance type — e.g. inf2.xlarge (2 NeuronCores, 32GB HBM)
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = [var.inferentia_instance_type]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            }
          ]
        }
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        # 10 min before consolidating — Neuron models have a long cold-start
        # due to JIT compilation when loading the .neff into the accelerator.
        consolidateAfter    = "10m"
      }
    }
  })

  depends_on = [kubectl_manifest.ec2_node_class_inferentia]
}
