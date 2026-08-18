variable "cluster_name" {
  description = "Nombre del cluster kind."
  type        = string
}

variable "worker_nodes" {
  description = "Cantidad de nodos worker."
  type        = number
  default     = 2
}
