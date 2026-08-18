output "cluster_name" {
  value = kind_cluster.este.name
}

output "endpoint" {
  value = kind_cluster.este.endpoint
}

output "kubeconfig_path" {
  value = kind_cluster.este.kubeconfig_path
}

output "client_certificate" {
  value     = kind_cluster.este.client_certificate
  sensitive = true
}

output "client_key" {
  value     = kind_cluster.este.client_key
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = kind_cluster.este.cluster_ca_certificate
  sensitive = true
}
