variable "resource_group_name" {
  type    = string
  default = "RG-TerraformDemo"
}

variable "location" {
  type    = string
  default = "Korea Central"
}

variable "virtual_network" {
  type    = string
  default = "zero-vnet"
}

variable "storage_account_name" {
  type    = string
  default = "zerotfsademo"
}

variable "keyvault_name" {
  description = "Azure Key Valut name"
  default     = "zerotfkvdemo"
}

variable "keyvault_secretname_web" {
  description = "Azure Key Valut Secret name"
  default     = "webadminpw"
}

variable "keyvault_secretname_db" {
  description = "Azure Key Valut Secret name"
  default     = "dbadminpw"
}