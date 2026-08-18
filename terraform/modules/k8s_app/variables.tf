variable "namespace" {
  type        = string
  description = "Namespace de la aplicacion."
}

variable "imagen" {
  type        = string
  description = "Imagen con tag inmutable."
}

variable "replicas" {
  type        = number
  default     = 2
  description = "Replicas iniciales."
}

variable "recursos" {
  description = "Requests y limits del contenedor."
  type = object({
    cpu_request     = string
    cpu_limit       = string
    memoria_request = string
    memoria_limit   = string
  })
}

variable "hpa" {
  description = "Configuracion del HorizontalPodAutoscaler."
  type = object({
    min_replicas     = number
    max_replicas     = number
    cpu_objetivo     = number
    memoria_objetivo = number
  })
}
