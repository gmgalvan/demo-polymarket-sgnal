################################################################################
# EFS Filesystem + Mount Targets
################################################################################

resource "aws_efs_file_system" "this" {
  creation_token = var.name
  encrypted      = true
  kms_key_id     = var.kms_key_id

  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_efs_mount_target" "this" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

################################################################################
# Security Group — allows NFS (2049) from the node security group
################################################################################

resource "aws_security_group" "efs" {
  name_prefix = "${var.name}-efs-"
  description = "Allow NFS access from EKS nodes to EFS"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-efs"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "nfs_ingress" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = var.node_security_group_id
  security_group_id        = aws_security_group.efs.id
  description              = "NFS from EKS nodes"
}

resource "aws_security_group_rule" "nfs_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.efs.id
  description       = "Allow all outbound"
}

################################################################################
# EFS CSI Driver — Helm release (optional)
################################################################################

resource "helm_release" "efs_csi_driver" {
  count = var.install_efs_csi_driver ? 1 : 0

  name       = "aws-efs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
  chart      = "aws-efs-csi-driver"
  namespace  = "kube-system"
  version    = var.efs_csi_driver_version

  set = [
    {
      name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.efs_csi[0].arn
    },
    {
      name  = "node.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.efs_csi[0].arn
    }
  ]
}

################################################################################
# IRSA for EFS CSI Driver
################################################################################

data "aws_iam_policy_document" "efs_csi_assume" {
  count = var.install_efs_csi_driver ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^arn:aws:iam::[0-9]+:oidc-provider\\//", "")}:sub"
      values   = ["system:serviceaccount:kube-system:efs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^arn:aws:iam::[0-9]+:oidc-provider\\//", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "efs_csi" {
  count = var.install_efs_csi_driver ? 1 : 0

  name               = "${var.name}-efs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.efs_csi_assume[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  count = var.install_efs_csi_driver ? 1 : 0

  role       = aws_iam_role.efs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

################################################################################
# StorageClass + PersistentVolume (Kubernetes manifests)
################################################################################

resource "kubectl_manifest" "storage_class" {
  count = var.create_storage_class ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "storage.k8s.io/v1"
    kind       = "StorageClass"
    metadata = {
      name = var.storage_class_name
    }
    provisioner = "efs.csi.aws.com"
    parameters = {
      provisioningMode = "efs-ap"
      fileSystemId     = aws_efs_file_system.this.id
      directoryPerms   = "700"
    }
    reclaimPolicy     = "Retain"
    volumeBindingMode = "Immediate"
  })

  depends_on = [helm_release.efs_csi_driver]
}
