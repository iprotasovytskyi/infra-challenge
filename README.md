# \# Hivemind Infra — Step-by-Step Setup

Below is the starting point README for the repository structure.
It will guide you from “zero” to a running **NGINX Ingress (NLB, internet-facing)** and the **greeter service**.
Improvement steps (**metrics-server**, **cluster-autoscaler with IRSA**, **HPA in the chart**) will be documented in later sections.

---

## 0) Prerequisites

- AWS profile in `~/.aws/credentials` named **hivemind**
- Installed tools: **Terraform**, **kubectl**, **helm**, **Docker**
- GitHub OIDC configured for CI (IAM block already contains required setup)

---

## Repository structure

```text
    infra-challenge/
    ├─ .github/
    │  └─ workflows/
    │     └─ build-and-push.yaml                  # CI: build & push image
    ├─ chart/                                     # Helm chart for greeter (Deployment/Service/Ingress + HPA)
    │  └─ templates/
    │     ├─ _helpers.tpl
    │     ├─ deployment.yaml
    │     ├─ hpa.yaml
    │     ├─ ingress.yaml
    │     └─ service.yaml
    ├─ greeter/
    │  ├─ .terraform/…                            # local TF files (ignored)
    │  └─ main.tf                                 # (Helm release of application via Terraform)
    ├─ infra/
    │  ├─ bootstrap/                              # S3 bucket for state + DynamoDB lock
    │  ├─ ecr/                                    # (ECR)
    │  ├─ eks/                                    # EKS cluster & nodegroups
    │  ├─ iam/                                    # Human admin + GitHub OIDC + CI role
    │  ├─ ingress/                                # Helm release of ingress-nginx via Terraform
    │  ├─ modules/
    │  │  └─ iam/                                 # IAM submodule (used in infra/iam)
    │  └─ vpc/                                    # VPC with public/private subnets, ELB tags
    ├─ Dockerfile                                 # greeter container image
    └─ greeter.go                                 # current service code
```

---

### 1) Bootstrap (Terraform state & lock)

First, we need to create infrastructure for storing Terraform state and ensuring safe concurrent runs.  
This includes an **S3 bucket** for state and a **DynamoDB table** for state locking.

### Steps
1. Go to `infra/bootstrap/`
2. Run:
```bash
terraform init
terraform apply
```

### Input variables

```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket" {
  description = "Globally-unique S3 bucket name for TF state (e.g., hivemind-tf-state-ihor-dev)"
  type        = string
  default     = "hivemind-tf-state"
}

variable "lock_table" {
  description = "DynamoDB table name for TF state lock"
  type        = string
  default     = "tf-lock-hivemind-dev"
}
```

---

### 2) Creating network components

Next, we need to create network components.  
This includes a **VPC**, **public/private subnets**, **ELB tags**.

### Steps
1. Go to `infra/vpc/`
2. Run:
```bash
terraform init
terraform apply
```

```text
Creates:
3 public and 3 private subnets in different AZs
Tags for NLB/ELB and EKS
```

### Input variables

```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "project" {
  description = "Project tag"
  type        = string
  default     = "hivemind-infra-challenge"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "hivemind"
}

variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "hivemind"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "public_subnets" {
  description = "Public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.20.0.0/20", "10.20.16.0/20", "10.20.32.0/20"]
}

variable "private_subnets" {
  description = "Private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.20.128.0/20", "10.20.144.0/20", "10.20.160.0/20"]
}
```

---

### 3) IAM (GitHub OIDC + CI role + admin)

### Steps
1. Go to `infra/iam/`
2. Run:
```bash
terraform init
terraform apply
```

```text
Includes:
OIDC provider for GitHub
Role ci-deploy with permissions for: ECR, EKS, ELB/NLB annotations, Helm via kube access
human admin user
```

### Used codebase and module to store separated access documents

---

### 4) ECR

### Steps
1. Go to `infra/ecr/`
2. Run:
```bash
terraform init
terraform apply
```

```bash
aws ecr get-login-password --profile hivemind --region eu-central-1 \
| docker login --username AWS --password-stdin <account>.dkr.ecr.eu-central-1.amazonaws.com

docker build -t greeter:latest .
docker tag greeter:latest <account>.dkr.ecr.eu-central-1.amazonaws.com/greeter:latest
docker push <account>.dkr.ecr.eu-central-1.amazonaws.com/greeter:latest
```

### Input variables

```hcl
variable "region" {
  description = "AWS region, e.g. eu-central-1"
  type        = string
  default = "eu-central-1"
}

variable "repo_name" {
  description = "ECR repository name (e.g., greeter)"
  type        = string
  default = "greeter"
}

variable "environment" {
  description = "Tag value for Environment"
  type        = string
  default     = "hivemind"
}

variable "force_delete" {
  description = "If true, allow deleting repo with images (useful for dev)"
  type        = bool
  default     = false
}

variable "enable_lifecycle" {
  description = "Enable a simple lifecycle rule for untagged images"
  type        = bool
  default     = true
}

variable "untagged_retention_days" {
  description = "Expire untagged images after N days"
  type        = number
  default     = 7
}

variable "attach_readonly_to_node_role" {
  description = "Attach AmazonEC2ContainerRegistryReadOnly to the provided node IAM role"
  type        = bool
  default     = false
}

variable "node_role_name" {
  description = "EKS node IAM role name (not ARN). Leave empty to skip attach"
  type        = string
  default     = ""
}
```

---

### 5) EKS

```text
Creates:
EKS with managed node group (2 k8s nodes)
```

### Steps
1. Go to `infra/eks/`
2. Run:
```bash
terraform init
terraform apply
```

```bash
aws eks update-kubeconfig \
--region eu-central-1 \
--name hive-eks \
--profile hivemind \
--role-arn arn:aws:iam::959413831332:role/eks-human-admin
```

### Input variables

```hcl
# -----------------------------
# General / Region
# -----------------------------
variable "region" {
  description = "AWS region for EKS"
  type        = string
  default     = "eu-central-1"
}

# -----------------------------
# VPC
# -----------------------------
variable "vpc_id" {
  description = "VPC ID where EKS will be created"
  type        = string
  default     = "vpc-09539bf7c455d4246"
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS worker nodes"
  type        = list(string)
  default     = ["subnet-0cb0686e33097c0e9", "subnet-0b663bd1771a08d88", "subnet-04e63728632af7300"]
}

# -----------------------------
# Cluster settings
# -----------------------------
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "hive-eks"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.32"
}

# -----------------------------
# Optional managed node group (single)
# -----------------------------
variable "create_node_group" {
  description = "Whether to create a managed node group"
  type        = bool
  default     = true
}

variable "node_group_name" {
  description = "Managed node group name (used when create_node_group = true)"
  type        = string
  default     = "default"
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t2.small"]
}

variable "node_capacity_type" {
  description = "Capacity type for the node group (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be either \"ON_DEMAND\" or \"SPOT\"."
  }
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 2
}

# -----------------------------
# Modern access (EKS Access Entries, no aws-auth)
# -----------------------------
variable "human_admin_role_arn" {
  description = "IAM Role ARN for human admin access (e.g., AWS SSO role)"
  type        = string
  default = "arn:aws:iam::959413831332:role/eks-human-admin"
}

variable "ci_role_arn" {
  description = "IAM Role ARN for CI/CD (GitHub OIDC) with limited access"
  type        = string
  default = "arn:aws:iam::959413831332:role/eks-ci-role"
}

# -----------------------------
# CI access scope/policy
# -----------------------------
variable "ci_namespaces" {
  description = "Namespaces that CI can access (namespace-scoped access)"
  type        = list(string)
  default     = ["greeter"]
}

variable "ci_access_policy_arn" {
  description = "Managed EKS access policy for CI (e.g., AmazonEKSEditPolicy)"
  type        = string
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
}

variable "ingress_allowed_cidrs" {
  description = "CIDR ranges allowed to reach ingress-nginx via NLB (use 0.0.0.0/0 for internet-facing; use VPC CIDR(s) for internal)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
```

---

### 6) Ingress Controller (ingress-nginx, NLB internet-facing)

```text
Creates:
HA ingress-nginx controller with NLB (multi AZ)
Created by Terraform and official Helm chart
Provided values.yaml file for configuration
```

### Steps
1. Go to `infra/ingress/`
2. Run:
   ```bash
   terraform init
   terraform apply
   ```

   ```yaml
   controller:
    service:
    type: LoadBalancer
    externalTrafficPolicy: "Local"
    annotations:
        service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
        service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
        service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
        service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
        service.beta.kubernetes.io/aws-load-balancer-subnets: "subnet-AAAA,subnet-BBBB,subnet-CCCC"
   ```

### Input variables

```hcl
# ============================
# Ingress NGINX Helm variables
# ============================

variable "region" {
  description = "AWS region used by the AWS/Kubernetes/Helm providers."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "EKS cluster name to discover API endpoint and CA."
  type        = string
  default     = "hive-eks"
}

variable "human_admin_role_arn" {
  description = "IAM role ARN to assume for Kubernetes auth (should have EKS Access Entry, e.g. ClusterAdmin)."
  type        = string
  default     = "arn:aws:iam::959413831332:role/eks-human-admin"
}

variable "namespace" {
  description = "Kubernetes namespace for the ingress-nginx release."
  type        = string
  default     = "ingress-nginx"
}

variable "create_namespace" {
  description = "Whether to create the namespace for the Helm release."
  type        = bool
  default     = true
}

variable "chart_version" {
  description = "Pinned Helm chart version for ingress-nginx."
  type        = string
  default     = "4.12.1"
}

variable "lb_cidrs" {
  description = "CIDRs для відкриття на SG нод"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
```

---

### 7) Greeter application (Helm via Terraform)

```text
Creates:
Release chart to deploy to the env
```

### Steps
1. Go to `greeter`
2. Run:
   ```bash
   terraform init
   terraform apply
   ```
```yaml
image:
  repository: 959413831332.dkr.ecr.eu-central-1.amazonaws.com/greeter
  tag: "latest"
  pullPolicy: IfNotPresent

replicaCount: 2

env:
  HELLO_TAG: "dev"

service:
  port: 8080
  type: ClusterIP

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 60
  targetMemoryUtilizationPercentage: 70

ingress:
  enabled: true
  className: public-ingress
  hosts:
    - host: ""
      paths:
        - path: /
          pathType: Prefix
  tls: []

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

### Input variables

```hcl
# AWS & cluster targeting
variable "region" {
  description = "AWS region to operate in"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Target EKS cluster name"
  type        = string
  default     = "hive-eks"
}

# Release / namespace
variable "namespace" {
  description = "Kubernetes namespace to install the Helm release into"
  type        = string
  default     = "greeter"
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "greeter"
}

# Container image (ECR)
variable "image_repository" {
  description = "Full image repository (ECR), e.g. <ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com/greeter"
  type        = string
  default     = "959413831332.dkr.ecr.eu-central-1.amazonaws.com/greeter"
}

variable "image_tag" {
  description = "Image tag to deploy"
  type        = string
  default     = "latest"
}

# Application configuration
variable "hello_tag" {
  description = "Value for HELLO_TAG environment variable passed to the app"
  type        = string
  default     = "dev"
}
```

---

### 8) CI/CD (GitHub Actions)

```text
Creates:
GitHub Actions pipeline with 2 jobs
To build docker image and deploy to hte env
Using separate role to control access
```

```yaml
name: Build & Deploy
on:
  push:
    branches: [ "main" ]

env:
  AWS_REGION: eu-central-1
  AWS_ACCOUNT_ID: 959413831332
  ECR_REPOSITORY: greeter

permissions:
  id-token: write
  contents: read

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    outputs:
      image_tag: ${{ steps.meta.outputs.short_sha }}
      image_uri: ${{ steps.meta.outputs.image_uri }}
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ env.AWS_ACCOUNT_ID }}:role/eks-ci-role
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        run: |
          aws ecr get-login-password --region $AWS_REGION \
            | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

      - name: Compute image meta
        id: meta
        run: |
          SHORT_SHA="${GITHUB_SHA::7}"
          echo "short_sha=$SHORT_SHA" >> "$GITHUB_OUTPUT"
          echo "image_uri=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$SHORT_SHA" >> "$GITHUB_OUTPUT"

      - name: Build & Push image
        run: |
          docker build -t "${{ steps.meta.outputs.image_uri }}" -f Dockerfile .
          docker push "${{ steps.meta.outputs.image_uri }}"

  deploy:
    needs: build-and-push
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ env.AWS_ACCOUNT_ID }}:role/eks-ci-role
          aws-region: ${{ env.AWS_REGION }}

      - name: Set up Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init/Apply (greeter)
        working-directory: ./greeter
        env:
          TF_VAR_image_repository: ${{ env.AWS_ACCOUNT_ID }}.dkr.ecr.${{ env.AWS_REGION }}.amazonaws.com/${{ env.ECR_REPOSITORY }}
          TF_VAR_image_tag: ${{ needs.build-and-push.outputs.image_tag }}
          TF_VAR_hello_tag: ${{ github.run_number }}
        run: |
          terraform init -input=false
          terraform apply -input=false -auto-approve \
            -var image_repository="${TF_VAR_image_repository}" \
            -var image_tag="${TF_VAR_image_tag}" \
            -var hello_tag="${TF_VAR_hello_tag}"
```

---

### Dockerfile was prepared as multi-stage and to run process from non-root user based on the best practices

```dockerfile
# --- Build stage --------------------------------------------------------------
FROM golang:1.22-alpine AS build
WORKDIR /src

# Install build deps (optional but handy)
RUN apk add --no-cache ca-certificates

# Copy sources
# If you have go.mod/go.sum, keep these two lines first for better caching:
# COPY go.mod go.sum ./
# RUN go mod download
COPY . .

# Build static binary
ENV CGO_ENABLED=0 GOOS=linux GOARCH=amd64
RUN go build -trimpath -ldflags="-s -w" -o /out/greeter ./greeter.go

# --- Runtime stage ------------------------------------------------------------
# Distroless = tiny, no shell, runs as nonroot by default
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app

# Copy binary
COPY --from=build /out/greeter /app/greeter

# App listens on 8080
EXPOSE 8080

# Optional default; override in k8s with env
ENV HELLO_TAG=dev

# Run as non-root
USER nonroot
ENTRYPOINT ["/app/greeter"]
```

---

### Helm chart was prepared ass simple as possible
### Prepared Deployment, Service, Ingress and HPA. Continuous Deployment configured to use HELM and Terraform.

---

# Seps for the improvements

### Metrics-Server

```text
To have aviability gather metrics from the k8s entities
```
```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system \
  --set args="{--kubelet-insecure-tls}"
```

---

### KSM

```text
kube-state-metrics (KSM) is a simple service that listens to the Kubernetes API server,
and generates metrics about the state of the objects.
```

---

### Cluster-Autoscaler (IRSA)
```text
Ensure your AWS & kubectl environment is properly set - it should be set to the AWS account/env and K8s-cluster where you are installing the addon.
Check both!
```

```yaml
resources:
  limits:
    cpu: 500m
    memory: 1Gi
  requests:
    cpu: 100m
    memory: 300Mi

extraArgs:
  scale-down-utilization-threshold: 0.85
```

```shell
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}' | cut -f 2 -d "/")
helm upgrade --install -n kube-system cluster-autoscaler <cluster-autoscaler-X.YY.ZZZ.tgz> \
  --set 'autoDiscovery.clusterName'=${CLUSTER_NAME} \
  --set 'awsRegion'=eu-central-1 \
  --set 'cloudProvider'=aws \
  --set 'nameOverride'=cluster-autoscaler \
  -f values.all.yaml
  --wait
```

TLS
``` txt
Add cert-manager
Enable tls in ingress.yaml
Add domain to provide readable DNA name
and finish Ingress configuration
```
