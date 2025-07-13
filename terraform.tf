################################################################################
# 0) Provider & locals
################################################################################
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.99.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "11759609-bea9-4c84-969e-7fc099d8cf52"
}


locals {
  location = "eastasia"
  rg_name  = "demo-aca-rg"
}

################################################################################
# 1) Core infrastructure
################################################################################
resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = local.location
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "demo-aca-law"
  daily_quota_gb      = 0.1
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "env" {
  name                       = "demo-aca-env"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  # Optional: drop the next block if you don’t need a vNet
  # (adds extra deployment time but hides outbound IPs)
  #internal_load_balancer_enabled = true
  #infrastructure_subnet_id       = azurerm_subnet.aca.id
}

################################################################################
# 2) Internal-only Redis App
################################################################################
resource "azurerm_container_app" "redis" {
  name                         = "redis"
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Single"

  template {
    container {
      name   = "redis"
      image  = "redis:7.2"
      cpu    = 0.25
      memory = "0.5Gi"
    }

    min_replicas = 0
    max_replicas = 1
  }

  ingress {
    target_port      = 6379
    transport        = "tcp"
    external_enabled = false # <— ***keeps Redis private***

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }


}

################################################################################
# 3) Public Web App
################################################################################
resource "azurerm_container_app" "web" {
  name                         = "web"
  resource_group_name          = azurerm_resource_group.rg.name
  container_app_environment_id = azurerm_container_app_environment.env.id
  revision_mode                = "Single"

  template {
    min_replicas = 0
    max_replicas = 1
    container {
      name   = "web"
      image  = "ghcr.io/mildronize/kubricate-demo-azure-global-2025:main"
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "REDIS_HOST"
        value = azurerm_container_app.redis.name # resolves via built-in DNS
      }
      env {
        name  = "REDIS_PORT"
        value = "6379"
      }
    }
  }

  ingress {
    external_enabled = true # <— ***public endpoint***
    target_port      = 8080
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}
