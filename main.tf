resource "azurerm_resource_group" "zero-rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "zero-vnet" {
  name                = "zero-vnet"
  location            = azurerm_resource_group.zero-rg.location
  resource_group_name = azurerm_resource_group.zero-rg.name
  address_space       = ["10.0.0.0/16"]
  # depends_on = [
  #   azurerm_resource_group.zero-rg
  # ]
}

resource "azurerm_subnet" "web-subnet" {
  name                 = "web-subnet"
  resource_group_name  = azurerm_resource_group.zero-rg.name
  virtual_network_name = azurerm_virtual_network.zero-vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "zero-pip" {
  name                = "web-pip"
  resource_group_name = azurerm_resource_group.zero-rg.name
  location            = azurerm_resource_group.zero-rg.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "zero-nic" {
  name                = "web-nic"
  location            = azurerm_resource_group.zero-rg.location
  resource_group_name = azurerm_resource_group.zero-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.web-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.zero-pip.id
  }

  # depends_on = [
  #   azurerm_virtual_network.zero-vnet
  # ]
}

data "azurerm_client_config" "current" {}

# Pull existing Key Vault from Azure
data "azurerm_key_vault" "zero-kv" {
  name                = var.keyvault_name
  resource_group_name = local.resource_group_name
}

data "azurerm_key_vault_secret" "kv_secret_web" {
  name         = var.keyvault_secretname_web
  key_vault_id = data.azurerm_key_vault.zero-kv.id
}

data "azurerm_key_vault_secret" "kv_secret_db" {
  name         = var.keyvault_secretname_db
  key_vault_id = data.azurerm_key_vault.zero-kv.id
}

resource "azurerm_windows_virtual_machine" "zero-vm" {
  name                = "web-win-vm"
  resource_group_name = azurerm_resource_group.zero-rg.name
  location            = azurerm_resource_group.zero-rg.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  admin_password      = data.azurerm_key_vault_secret.kv_secret_web.value
  network_interface_ids = [
    azurerm_network_interface.zero-nic.id,
  ]
  availability_set_id = azurerm_availability_set.zero-as.id

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  # depends_on = [
  #   azurerm_availability_set.zero-as
  # ]
}

resource "azurerm_managed_disk" "zero-mdisk" {
  name                 = "web-data-disk"
  location             = azurerm_resource_group.zero-rg.location
  resource_group_name  = azurerm_resource_group.zero-rg.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "10"
}

resource "azurerm_virtual_machine_data_disk_attachment" "zero-disk_attatch" {
  managed_disk_id    = azurerm_managed_disk.zero-mdisk.id
  virtual_machine_id = azurerm_windows_virtual_machine.zero-vm.id
  lun                = "10"
  caching            = "ReadWrite"
}

resource "azurerm_availability_set" "zero-as" {
  name                         = "webvm-as"
  location                     = azurerm_resource_group.zero-rg.location
  resource_group_name          = azurerm_resource_group.zero-rg.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2

  # depends_on = [
  #   azurerm_windows_virtual_machine.zero-vm
  # ]
}

resource "azurerm_storage_account" "zero-sa" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.zero-rg.name
  location                 = azurerm_resource_group.zero-rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  # public_network_access_enabled = true, if not 404 error will occur.
  public_network_access_enabled = true
}

resource "azurerm_storage_container" "zero-cont" {
  name                  = "data"
  storage_account_name  = azurerm_storage_account.zero-sa.name
  container_access_type = "blob"
}

# Updload the IIS configuration script as a blob to the Azure Storage Account
resource "azurerm_storage_blob" "zero-blob" {
  name                   = "IIS_Config.ps1"
  storage_account_name   = var.storage_account_name
  storage_container_name = azurerm_storage_container.zero-cont.name
  type                   = "Block"
  source                 = "IIS_Config.ps1"
}

resource "azurerm_virtual_machine_extension" "zero-vm_extension" {
  name               = "webvm-extension"
  virtual_machine_id = azurerm_windows_virtual_machine.zero-vm.id
  # publisher            = "Microsoft.Azure.Extensions"
  # type                 = "CustomScript"
  # type_handler_version = "2.0"
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  # depends_on = [
  #   azurerm_storage_blob.zero-blob
  # ]

  settings = <<SETTINGS
    {
      "fileUris": ["https://${azurerm_storage_account.zero-sa.name}.blob.core.windows.net/data/IIS_Config.ps1"],
      "commandToExecute": "powershell.exe -ExecutionPolicy Unrestricted -file \"./IIS_Config.ps1\""
    }
SETTINGS
}

resource "azurerm_network_security_group" "zero-nsg" {
  name                = "webvm-nsg"
  location            = azurerm_resource_group.zero-rg.location
  resource_group_name = azurerm_resource_group.zero-rg.name
}

## NSG Inbound Rule for AppTier Subnets
resource "azurerm_network_security_rule" "zero-nsg_rule" {
  for_each                    = local.app_inbound_ports_map
  name                        = "Rule-Port-${each.value}"
  priority                    = each.key
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.zero-rg.name
  network_security_group_name = azurerm_network_security_group.zero-nsg.name
}

resource "azurerm_subnet_network_security_group_association" "zero-nsg_association" {
  subnet_id                 = azurerm_subnet.web-subnet.id
  network_security_group_id = azurerm_network_security_group.zero-nsg.id
}

# resource "azurerm_key_vault" "zero-key_vault" {
#   name                        = "zerotfkvdemo"
#   location                    = azurerm_resource_group.zero-rg.location
#   resource_group_name         = azurerm_resource_group.zero-rg.name
#   enabled_for_disk_encryption = true
#   tenant_id                   = data.azurerm_client_config.current.tenant_id
#   soft_delete_retention_days  = 7
#   purge_protection_enabled    = false

#   sku_name = "standard"

#   access_policy {
#     tenant_id = data.azurerm_client_config.current.tenant_id
#     object_id = data.azurerm_client_config.current.object_id

#     key_permissions = [
#       "Get",
#     ]

#     secret_permissions = [
#       "Get", "Backup", "Delete", "List", "Purge", "Recover", "Restore", "Set",
#     ]

#     storage_permissions = [
#       "Get",
#     ]
#   }
# }

resource "azurerm_mssql_server" "zero-sql_server" {
  name                         = "zeromssqlserver"
  resource_group_name          = azurerm_resource_group.zero-rg.name
  location                     = azurerm_resource_group.zero-rg.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = data.azurerm_key_vault_secret.kv_secret_db.value
  minimum_tls_version          = "1.2"

  # azuread_administrator {
  #   login_username = "AzureAD Admin"
  #   object_id      = "00000000-0000-0000-0000-000000000000"
  # }
}

resource "azurerm_mssql_database" "zero-sql_db" {
  name           = "sqldatabase"
  server_id      = azurerm_mssql_server.zero-sql_server.id
  collation      = "SQL_Latin1_General_CP1_CI_AS"
  # license_type   = "BasePrice"
  max_size_gb    = 1
  read_scale     = true
  sku_name       = "BC_Gen5_2"
  # zone_redundant = true
}

resource "azurerm_mssql_firewall_rule" "zero-sql_fw_rule" {
  name             = "sqldatabaseFirewallRule"
  server_id        = azurerm_mssql_server.zero-sql_server.id
  start_ip_address = "58.151.93.17"
  end_ip_address   = "58.151.93.17"
}