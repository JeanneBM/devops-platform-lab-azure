output "resource_group_name" {
  value = azurerm_resource_group.lab.name
}

output "node_resource_group_name" {
  value = azurerm_kubernetes_cluster.lab.node_resource_group
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.lab.name
}

output "acr_name" {
  value = azurerm_container_registry.lab.name
}

output "acr_login_server" {
  value = azurerm_container_registry.lab.login_server
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.lab.oidc_issuer_url
}

output "subscription_id" {
  value = var.subscription_id
}
