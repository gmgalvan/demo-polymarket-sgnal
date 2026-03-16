# ── EC2NodeClass ──────────────────────────────────────────────────────────────

resource "kubectl_manifest" "ec2_node_class_arm" {
  count = var.enable_karpenter_nodepools ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "arm-general"
    }
    spec = {
      amiFamily = "AL2023"
      amiSelectorTerms = [
        {
          ssmParameter = local.arm_ami_ssm_parameter
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

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "ec2_node_class_gpu" {
  count = var.enable_karpenter_nodepools ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "gpu-inference"
    }
    spec = {
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

resource "kubectl_manifest" "ec2_node_class_inferentia" {
  count = var.enable_karpenter_nodepools ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "neuron-inference"
    }
    spec = {
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
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["arm64"]
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = [var.core_node_instance_type]
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
        consolidateAfter    = "5m"
      }
    }
  })

  depends_on = [kubectl_manifest.ec2_node_class_arm]
}

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
            accelerator = "nvidia-l40s"
            workload    = "gpu"
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
              key    = "nvidia.com/gpu"
              value  = "true"
              effect = "NoSchedule"
            }
          ]
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
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
            accelerator = "aws-inferentia2"
            workload    = "neuron"
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
              key    = "aws.amazon.com/neuron"
              value  = "true"
              effect = "NoSchedule"
            }
          ]
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
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
        consolidateAfter    = "10m"
      }
    }
  })

  depends_on = [kubectl_manifest.ec2_node_class_inferentia]
}
