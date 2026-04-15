terraform {
  required_providers {
    azurerm = {
        source = "hashicorp/azurerm"
        version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# Create a resource group
resource "azurerm_resource_group" "rg" {
  name     = "HAADTechRG"
  location = "East Asia"
}

# Create azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "haadtechacr2026"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# 1. Tạo Log Analytics Workspace (Để lưu log và monitor hệ thống, sau này sẽ kết nối với Application Insights)
resource "azurerm_log_analytics_workspace" "law" {
  name                = "haadtech-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# 2. Tạo Application Insights (Dùng để monitor traffic 4 người)
resource "azurerm_application_insights" "appinsights" {
  name                = "haadtech-appinsights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.law.id
}

# 3. Tạo Azure Kubernetes Service (AKS) 
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "haadtech-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "haadtechaks"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_B2ls_v2" #
  }

  identity {
    type = "SystemAssigned"
  }
}

# 4. Lấy thông tin tenant hiện tại để cấu hình Key Vault
data "azurerm_client_config" "current" {}

# 5. Tạo Azure Key Vault
resource "azurerm_key_vault" "kv" {
  name                        = "haadtechkv2026" 
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
}

# 6. Tạo App Service Plan (Gói tài nguyên cho Web App)
resource "azurerm_service_plan" "asp" {
  name                = "haadtech-asp"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "B1" 
}

# 7. Tạo Azure Web App 
resource "azurerm_linux_web_app" "webapp" {
  name                = "haadtech-web-2026" 
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_service_plan.asp.location
  service_plan_id     = azurerm_service_plan.asp.id

  site_config {
    application_stack {
      node_version = "18-lts" 
    }
    always_on = false # Tắt cái này để tiết kiệm credit
  }

  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.appinsights.instrumentation_key
  }
}

# 8. Tạo Virtual Network (Mạng ảo cho VM)
resource "azurerm_virtual_network" "vnet" {
  name                = "haadtech-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# 9. Tạo Subnet
resource "azurerm_subnet" "subnet" {
  name                 = "haadtech-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# 10. Tạo Public IP (Để truy cập Jenkins qua trình duyệt)
resource "azurerm_public_ip" "pip" {
  name                = "haadtech-jenkins-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"   # <--- Đổi từ Dynamic sang Static
  sku                 = "Standard" # <--- Khai báo rõ ràng bắt buộc dùng gói Standard
}

# 11. Tạo Network Security Group (Mở cửa cho Port 22 và 8080)
resource "azurerm_network_security_group" "nsg" {
  name                = "haadtech-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Jenkins"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# 12. Tạo Card mạng (NIC)
resource "azurerm_network_interface" "nic" {
  name                = "haadtech-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# Gắn Rule bảo mật vào Card mạng
resource "azurerm_network_interface_security_group_association" "nsg_nic" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# 13. Tạo Máy ảo Ubuntu (VM) chạy Jenkins
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "haadtech-jenkins-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2ls_v2"
  admin_username      = "adminuser"
  
  admin_password                  = "Sonpham8112005@"  
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}