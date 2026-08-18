variable "cluster_name" {
  description = "Nombre del cluster Kubernetes local (kind)."
  type        = string
  default     = "pf-cloud"
}

variable "worker_nodes" {
  description = "Cantidad de nodos worker. FinOps: mas nodos = mas consumo local."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_nodes >= 1 && var.worker_nodes <= 4
    error_message = "worker_nodes debe estar entre 1 y 4."
  }
}

variable "namespace" {
  description = "Namespace donde se despliega la aplicacion."
  type        = string
  default     = "pf-app"
}

variable "app_image" {
  description = "Imagen de la aplicacion, con tag inmutable (nunca 'latest')."
  type        = string
  default     = "ghcr.io/USUARIO/pf-cloud-api:1.0.0"
}

variable "app_replicas" {
  description = "Replicas iniciales. El HPA ajusta desde este valor."
  type        = number
  default     = 2
}

variable "recursos" {
  description = "Requests y limits del contenedor. Base del calculo FinOps."
  type = object({
    cpu_request     = string
    cpu_limit       = string
    memoria_request = string
    memoria_limit   = string
  })
  default = {
    cpu_request     = "100m"
    cpu_limit       = "500m"
    memoria_request = "128Mi"
    memoria_limit   = "256Mi"
  }
}

variable "hpa" {
  description = "Parametros de auto-escalado horizontal."
  type = object({
    min_replicas     = number
    max_replicas     = number
    cpu_objetivo     = number
    memoria_objetivo = number
  })
  default = {
    min_replicas     = 2
    max_replicas     = 10
    cpu_objetivo     = 70
    memoria_objetivo = 80
  }
}

variable "instalar_monitoreo" {
  description = "Si es true, instala Prometheus y Grafana via Helm."
  type        = bool
  default     = true
}

variable "costo_por_mb" {
  description = "Costo simulado por MB/mes, usado en el output de FinOps."
  type        = number
  default     = 0.02
}
