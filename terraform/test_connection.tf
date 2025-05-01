# 1) Tell Terraform how to find your K3s kubeconfig
#    Adjust the path to wherever you placed k3s.yaml after Ansible fetch.
provider "kubernetes" {
  config_path = "${path.module}/k3s.yaml"
}

# 2) Use a data source to read the "kube-system" namespace
data "kubernetes_namespace" "kube_system" {
  metadata {
    name = "kube-system"
  }
}

# 3) Output the namespace UID so we can confirm Terraform actually read it.
output "kube_system_uid" {
  value       = data.kubernetes_namespace.kube_system.metadata.0.uid
  description = "Unique ID of the kube-system namespace."
}