output "cluster_name" {
  description = "Nombre del cluster creado."
  value       = module.cluster.cluster_name
}

output "kubeconfig_path" {
  description = "Ruta del kubeconfig generado por kind."
  value       = module.cluster.kubeconfig_path
}

output "namespace_app" {
  description = "Namespace de la aplicacion."
  value       = module.app.namespace
}

output "service_app" {
  description = "Service que expone la aplicacion."
  value       = module.app.service_name
}

# --- FinOps: estimacion de costo segun los requests declarados -------------
output "finops_estimacion" {
  description = "Costo mensual estimado segun memoria solicitada y replicas."
  value = {
    memoria_request_mb   = tonumber(replace(var.recursos.memoria_request, "Mi", ""))
    replicas_minimas     = var.hpa.min_replicas
    replicas_maximas     = var.hpa.max_replicas
    costo_por_mb_mes     = var.costo_por_mb
    costo_minimo_mes_usd = tonumber(replace(var.recursos.memoria_request, "Mi", "")) * var.hpa.min_replicas * var.costo_por_mb
    costo_maximo_mes_usd = tonumber(replace(var.recursos.memoria_request, "Mi", "")) * var.hpa.max_replicas * var.costo_por_mb
  }
}
