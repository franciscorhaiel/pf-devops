# ---------------------------------------------------------------------------
# Modulo 1: provisiona el cluster Kubernetes local con kind.
# En un entorno cloud este modulo se reemplaza por eks/gke sin tocar el resto.
# ---------------------------------------------------------------------------
module "cluster" {
  source = "./modules/kind_cluster"

  cluster_name = var.cluster_name
  worker_nodes = var.worker_nodes
}

# Los providers de Kubernetes y Helm consumen el kubeconfig que genera el modulo.
provider "kubernetes" {
  host                   = module.cluster.endpoint
  client_certificate     = module.cluster.client_certificate
  client_key             = module.cluster.client_key
  cluster_ca_certificate = module.cluster.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = module.cluster.endpoint
    client_certificate     = module.cluster.client_certificate
    client_key             = module.cluster.client_key
    cluster_ca_certificate = module.cluster.cluster_ca_certificate
  }
}

# ---------------------------------------------------------------------------
# Modulo 2: despliega la aplicacion (namespace, deployment, service, HPA).
# El Ingress y el ingress-controller se manejan por manifiestos en k8s/.
# ---------------------------------------------------------------------------
module "app" {
  source = "./modules/k8s_app"

  namespace = var.namespace
  imagen    = var.app_image
  replicas  = var.app_replicas
  recursos  = var.recursos
  hpa       = var.hpa

  depends_on = [module.cluster]
}

# ---------------------------------------------------------------------------
# Monitoreo opcional: kube-prometheus-stack incluye Prometheus + Grafana.
# Se puede desactivar con instalar_monitoreo=false para ahorrar recursos.
# ---------------------------------------------------------------------------
resource "kubernetes_namespace" "monitoring" {
  count = var.instalar_monitoreo ? 1 : 0

  metadata {
    name = "monitoring"
    labels = {
      "proyecto" = "pf-cloud"
    }
  }

  depends_on = [module.cluster]
}

resource "helm_release" "prometheus_stack" {
  count = var.instalar_monitoreo ? 1 : 0

  name       = "monitoreo"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "66.2.1"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  # Valores acotados para que corra en una notebook.
  values = [file("${path.module}/../monitoring/values-prometheus.yaml")]

  timeout = 900
  wait    = true
}
