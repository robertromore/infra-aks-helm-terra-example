variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "monorepo-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "East US"
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "monorepo-aks"
}

variable "github_username" {
  description = "GitHub username for GHCR access"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token for GHCR access"
  type        = string
  sensitive   = true
}

variable "github_email" {
  description = "GitHub email for GHCR access"
  type        = string
  sensitive   = true
}

variable "node_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "VM size for nodes"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28.3"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "staging"
    Project     = "monorepo"
  }
}
