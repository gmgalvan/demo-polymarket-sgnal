variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

# ── lv-2 remote state (EKS) ──────────────────────────────────────────────────

variable "eks_state_bucket" {
  description = "S3 bucket containing lv-2 EKS Terraform state."
  type        = string
  default     = "352-demo-dev-s3b-tfstate-backend"
}

variable "eks_state_key" {
  description = "S3 key for lv-2 EKS Terraform state."
  type        = string
  default     = "dev/lv-2-core-compute/eks/terraform.tfstate"
}

variable "eks_state_region" {
  description = "Region where lv-2 EKS state backend lives."
  type        = string
  default     = "us-east-1"
}

# ── cert-manager (KServe dependency) ─────────────────────────────────────────

variable "install_cert_manager" {
  description = "Install cert-manager. Required by KServe for webhook TLS certificates."
  type        = bool
  default     = true
}

variable "cert_manager_chart_version" {
  description = "cert-manager Helm chart version. null = latest."
  type        = string
  default     = "v1.14.5"
  nullable    = true
}

# ── KServe ────────────────────────────────────────────────────────────────────

variable "install_kserve" {
  description = "Install KServe inference serving controller."
  type        = bool
  default     = true
}

variable "kserve_chart_version" {
  description = "KServe Helm chart version. null = latest."
  type        = string
  default     = "v0.13.0"
  nullable    = true
}

variable "kserve_namespace" {
  description = "Namespace where KServe is installed."
  type        = string
  default     = "kserve"
}

# ── KubeRay ───────────────────────────────────────────────────────────────────

variable "install_kuberay" {
  description = "Install KubeRay operator for Ray distributed compute clusters."
  type        = bool
  default     = true
}

variable "kuberay_chart_version" {
  description = "KubeRay operator Helm chart version. null = latest."
  type        = string
  default     = "1.2.2"
  nullable    = true
}

variable "kuberay_namespace" {
  description = "Namespace where KubeRay operator is installed."
  type        = string
  default     = "kuberay-system"
}

# ── NVIDIA NIM Operator ───────────────────────────────────────────────────────

variable "install_nim_operator" {
  description = "Install NVIDIA NIM Operator for managed NIM microservice deployments."
  type        = bool
  default     = true
}

variable "nim_operator_chart_version" {
  description = "NVIDIA NIM Operator Helm chart version. null = latest."
  type        = string
  default     = "1.0.0"
  nullable    = true
}

variable "nim_operator_namespace" {
  description = "Namespace where the NIM Operator is installed."
  type        = string
  default     = "nim-operator"
}

variable "ngc_api_key" {
  description = "NVIDIA NGC API key. Required to pull NIM container images from nvcr.io."
  type        = string
  sensitive   = true
  default     = ""
}
