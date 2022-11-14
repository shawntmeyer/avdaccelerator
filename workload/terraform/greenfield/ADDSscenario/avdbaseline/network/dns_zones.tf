# Creating a Private DNS Zone for the Storage Private Endpoints
resource "azurerm_private_dns_zone" "pe-dns-zone" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.net.name
  tags                = local.tags
  lifecycle { ignore_changes = [tags] }
}

resource "azurerm_private_dns_zone_virtual_network_link" "filelink" {
  name                  = "azfilelink"
  resource_group_name   = azurerm_resource_group.net.name
  private_dns_zone_name = azurerm_private_dns_zone.pe-dns-zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  tags                  = local.tags
  lifecycle { ignore_changes = [tags] }
}

# Creating a Private DNS Zone for the Key Vault Endpoints
resource "azurerm_private_dns_zone" "key-dns-zone" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.net.name
  tags                = local.tags

  lifecycle { ignore_changes = [tags] }
}

# Linking DNS Zone to the VNET
resource "azurerm_private_dns_zone_virtual_network_link" "netlink" {
  name                  = "keydnsvnet_link"
  resource_group_name   = azurerm_resource_group.net.name
  private_dns_zone_name = azurerm_private_dns_zone.key-dns-zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  tags                  = local.tags

  lifecycle { ignore_changes = [tags] }
}