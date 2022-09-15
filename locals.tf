locals {
  resource_group_name = "RG-KV4TF"
  location            = "Korea Central"
}

locals {
  app_inbound_ports_map = {
    "100" : "80", # If the key starts with a number, you must use the colon syntax ":" instead of "="
    "110" : "3389"
  }
}