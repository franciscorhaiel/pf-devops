# Copiar a terraform.tfvars y ajustar. terraform.tfvars esta en .gitignore.
cluster_name = "pf-cloud"
worker_nodes = 2
namespace    = "pf-app"
app_image    = "ghcr.io/franciscorhaiel/pf-cloud-api:1.0.0"
app_replicas = 2

instalar_monitoreo = true
costo_por_mb       = 0.02
