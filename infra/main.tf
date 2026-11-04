data "azurerm_client_config" "current" {}

locals {
  name = "${var.prefix}-${var.suffix}"
  tags = {
    project     = "devops-platform-lab-azure"
    environment = "learning"
    lifecycle   = "ephemeral"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_container_registry" "lab" {
  name                = "${var.prefix}${var.suffix}acr"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

resource "azurerm_kubernetes_cluster" "lab" {
  name                              = "aks-${local.name}"
  location                          = azurerm_resource_group.lab.location
  resource_group_name               = azurerm_resource_group.lab.name
  node_resource_group               = "rg-${local.name}-nodes"
  dns_prefix                        = local.name
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = "Free"
  role_based_access_control_enabled = true
  local_account_disabled            = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  tags                              = local.tags

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name            = "system"
    node_count      = 2
    vm_size         = var.node_size
    os_disk_size_gb = 64
    os_disk_type    = "Managed"
    max_pods        = 30
    tags            = local.tags
  }

  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  api_server_access_profile {
    authorized_ip_ranges = [var.operator_cidr]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }
}

# Image pull belongs to the node identity, not to the application ServiceAccount.
resource "azurerm_role_assignment" "pull" {
  scope                            = azurerm_container_registry.lab.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.lab.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# Only the named operator receives Kubernetes administration, at this AKS scope.
resource "azurerm_role_assignment" "operator" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.operator_object_id
}

# The human builds/pushes locally; pods receive no registry push permission.
resource "azurerm_role_assignment" "operator_push" {
  scope                = azurerm_container_registry.lab.id
  role_definition_name = "AcrPush"
  principal_id         = var.operator_object_id
}


# Credential download is a control-plane permission distinct from Kubernetes RBAC.
resource "azurerm_role_assignment" "operator_credentials" {
  scope                = azurerm_kubernetes_cluster.lab.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.operator_object_id
}
