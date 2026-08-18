terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.32"
    }
  }
}

locals {
  etiquetas = {
    "app.kubernetes.io/name"       = "pf-cloud-api"
    "app.kubernetes.io/component"  = "api"
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

resource "kubernetes_namespace" "app" {
  metadata {
    name   = var.namespace
    labels = local.etiquetas
  }
}

# ResourceQuota: techo duro de consumo del namespace. Pilar FinOps: ningun
# deploy mal configurado puede consumir todo el cluster.
resource "kubernetes_resource_quota" "cuota" {
  metadata {
    name      = "cuota-namespace"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = "2"
      "requests.memory" = "2Gi"
      "limits.cpu"      = "4"
      "limits.memory"   = "4Gi"
      "pods"            = "15"
    }
  }
}

# LimitRange: valores por defecto para cualquier pod sin requests declarados.
resource "kubernetes_limit_range" "limites" {
  metadata {
    name      = "limites-default"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default_request = {
        cpu    = var.recursos.cpu_request
        memory = var.recursos.memoria_request
      }
      default = {
        cpu    = var.recursos.cpu_limit
        memory = var.recursos.memoria_limit
      }
    }
  }
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = "pf-cloud-api"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.etiquetas
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = { "app.kubernetes.io/name" = "pf-cloud-api" }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "1"
        max_unavailable = "0" # despliegue sin downtime
      }
    }

    template {
      metadata {
        labels = local.etiquetas
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8000"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        # Seguridad: sin root, sin escalada de privilegios
        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          fs_group        = 10001
        }

        container {
          name  = "api"
          image = var.imagen

          port {
            container_port = 8000
            name           = "http"
          }

          env {
            name  = "APP_VERSION"
            value = "1.0.0"
          }

          # Requests y limits: obligatorios para que el HPA funcione
          resources {
            requests = {
              cpu    = var.recursos.cpu_request
              memory = var.recursos.memoria_request
            }
            limits = {
              cpu    = var.recursos.cpu_limit
              memory = var.recursos.memoria_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8000
            }
            initial_delay_seconds = 10
            period_seconds        = 15
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 8000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "app" {
  metadata {
    name      = "pf-cloud-api"
    namespace = kubernetes_namespace.app.metadata[0].name
    labels    = local.etiquetas
  }

  spec {
    type     = "ClusterIP"
    selector = { "app.kubernetes.io/name" = "pf-cloud-api" }

    port {
      name        = "http"
      port        = 80
      target_port = 8000
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "app" {
  metadata {
    name      = "pf-cloud-api"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.app.metadata[0].name
    }

    min_replicas = var.hpa.min_replicas
    max_replicas = var.hpa.max_replicas

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.hpa.cpu_objetivo
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = var.hpa.memoria_objetivo
        }
      }
    }

    # Escalar rapido hacia arriba, lento hacia abajo: evita el flapping
    # que encarece la factura.
    behavior {
      scale_up {
        stabilization_window_seconds = 30
        select_policy                = "Max"
        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 30
        }
      }
      scale_down {
        stabilization_window_seconds = 300
        select_policy                = "Min"
        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 60
        }
      }
    }
  }
}

# PodDisruptionBudget: garantiza disponibilidad durante mantenimientos.
resource "kubernetes_pod_disruption_budget_v1" "app" {
  metadata {
    name      = "pf-cloud-api"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    min_available = 1
    selector {
      match_labels = { "app.kubernetes.io/name" = "pf-cloud-api" }
    }
  }
}
