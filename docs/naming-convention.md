# Naming Convention Standards

This document defines AWS resource naming and tagging standards for this project.

## 1. Base Structure

All AWS resources must follow this general structure whenever the service name length limit allows it.

Format:

`<project>-<environment>-<resource_type>-<descriptive_name>`

Variables:

- `project`: fixed value `352-demo`
- `environment`: environment identifier (for example: `dev`, `qa`, `stg`, `prod`)
- `resource_type`: 3-4 character standard AWS service/resource abbreviation (see table below)
- `descriptive_name`: specific resource purpose/function, lowercase and hyphen-separated

## 2. Resource Type Abbreviations

Based on the current architecture, use the following abbreviations:

| Category | AWS Service / Resource | Abbreviation |
|---|---|---|
| Networking | Virtual Private Cloud | `vpc` |
| Networking | Subnet | `sbn` |
| Networking | Route Table | `rtb` |
| Networking | Elastic IP | `eip` |
| Networking | NAT Gateway | `nat` |
| IAM | IAM Role | `iamr` |
| IAM | IAM Policy | `iamp` |
| Compute | Elastic Kubernetes Service (Cluster) | `eks` |
| Compute | EKS Managed Node Group | `mng` |
| Compute | Elastic Container Registry | `ecr` |
| Compute | Network Load Balancer | `nlb` |
| Observability | Amazon Managed Prometheus | `amp` |
| Observability | Amazon Managed Grafana | `amg` |

## 3. Applied Examples by Stack Level

Applying `<project>-<environment>-<resource_type>-<descriptive_name>` to project `352-demo` in environment `prod`:

### Level 0: Networking

- Primary VPC: `352-demo-prod-vpc-main`
- Public subnets:
  - `352-demo-prod-sbn-public-a`
  - `352-demo-prod-sbn-public-b`
  - `352-demo-prod-sbn-public-c`
- Private subnets (worker nodes):
  - `352-demo-prod-sbn-private-1`
- Intra subnets (control plane / ENIs):
  - `352-demo-prod-sbn-intra-1`

### Level 1: IAM & Security

- Cluster admin role: `352-demo-prod-iamr-cluster-admin`
- Reader role: `352-demo-prod-iamr-reader`

### Level 2: Core Compute

- EKS cluster: `352-demo-prod-eks-cluster`
  - Note: in some cases, `-cluster` can be omitted if redundant (`352-demo-prod-eks`)
- Critical addons node group: `352-demo-prod-mng-critical-addons`
- ECR repository: `352-demo-prod-ecr-app-images`

### Level 3: Kubernetes Addons (AWS resources created for K8s)

- Karpenter IAM role (IRSA): `352-demo-prod-iamr-karpenter`
- Load Balancer Controller IAM role: `352-demo-prod-iamr-aws-lbc`
- Network Load Balancer (created by LBC): `352-demo-prod-nlb-ingress`

### Level 4: Observability

- Prometheus workspace: `352-demo-prod-amp-workspace`
- Grafana workspace: `352-demo-prod-amg-dashboard`

## 4. Tagging Convention Policy

Resource names are important, but AWS tags are mandatory for cost management (FinOps), governance, and operational filtering.

All Terraform-managed resources should include a base set of tags (preferably defined with AWS provider `default_tags` in Terraform).

Recommended required tags:

| Key | Description / Value for this project |
|---|---|
| `Project` | `352-demo` |
| `Environment` | `prod` (or the corresponding dynamic environment) |
| `ManagedBy` | `terraform` |
| `StackLevel` | `level-0-networking`, `level-1-iam`, etc. |
| `Owner` | `devops-team` (or responsible team/area) |

