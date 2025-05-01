
terraform {
  cloud {
    hostname     = "app.terraform.io"
    organization = "fareed-digital"

    workspaces {
      name = "HomePiSpace"
    }
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"

    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.19.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }

  }
}