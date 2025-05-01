# http://k8s.anjikeesari.com/kubernetes/5-cert-manager/#step-3-install-cert-manager-helm-chart-using-terraform

variable "domain" {
  type    = string
  default = "fareed.digital"
}

variable "profile_app_image" {
  type    = string
  default = "fareed83/profile-site:latest"
}

# Deploy NGINX Ingress Controller
resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.ingressClassResource.default"
    value = "true"
  }
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.17.2"

  set {
    name  = "installCRDs"
    value = "true"
  }
}


resource "time_sleep" "wait_for_cert_manager_crds" {
  depends_on      = [helm_release.cert_manager]
  create_duration = "30s"
}

locals {
  clusterissuer = "clusterissuer.yaml"
}

# Create clusterissuer for nginx YAML file
data "kubectl_file_documents" "clusterissuer" {
  content = file(local.clusterissuer)
}

resource "kubectl_manifest" "clusterissuer" {
  for_each  = data.kubectl_file_documents.clusterissuer.manifests
  yaml_body = each.value
  depends_on = [
    data.kubectl_file_documents.clusterissuer,
    time_sleep.wait_for_cert_manager_crds // Wait until CRDs are established
  ]
}

# Deploy the Web App (simplified, without read_only_root_filesystem)
resource "kubernetes_deployment" "web_app" {
  metadata {
    name      = "profile-site"
    namespace = "default"
    labels = {
      app = "profile-site"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "profile-site"
      }
    }

    template {
      metadata {
        labels = {
          app = "profile-site"
        }
      }

      spec {
        # Declare the volume (emptyDir is writable by default)
        volume {
          name      = "nginx-cache"
          empty_dir {}
        }

        # Set pod-level security with fsGroup so volumes are group-owned by 101.
        security_context {
          fs_group = 101
        }

        container {
          name  = "profile-site"
          image = var.profile_app_image
          image_pull_policy = "Always"

          # Mount the volume where Nginx can write caches/temp files.
          volume_mount {
            name       = "nginx-cache"
            mount_path = "/var/cache/nginx"
          }

          port {
            container_port = 80
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            # Note: Removing read_only_root_filesystem ensures the container filesystem is writable.
            # Instead of making the entire filesystem read-only, we allow writes so that chown operations can succeed.
            capabilities {
              drop = ["ALL"]
              add  = ["CHOWN", "SETGID", "SETUID"]
            }
            # Optionally, if your image expects UID 101, you can uncomment these:
            # run_as_user  = 101
            # run_as_group = 101
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
}


# Create a Service for the Web App
resource "kubernetes_service" "web_service" {
  metadata {
    name      = "profile-site-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = kubernetes_deployment.web_app.metadata[0].labels.app
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}

# Ingress Resource for HTTPS with Redirect
resource "kubernetes_ingress_v1" "web_ingress" {
  depends_on = [
    helm_release.nginx_ingress,
    helm_release.cert_manager,
    # kubernetes_manifest.letsencrypt_issuer
    kubectl_manifest.clusterissuer
  ]


  metadata {
    name      = "profile-site-ingress"
    namespace = "default"
    annotations = {
      "cert-manager.io/cluster-issuer"                 = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
    }
  }

  spec {
    rule {
      host = var.domain
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.web_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    tls {
      secret_name = "profile-site-tls"
      hosts       = [var.domain]
    }
  }
}
