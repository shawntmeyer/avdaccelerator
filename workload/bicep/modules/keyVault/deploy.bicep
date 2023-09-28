targetScope = 'subscription'

// ========== //
// Parameters //
// ========== //
@sys.description('AVD workload subscription ID, multiple subscriptions scenario')
param subscriptionId string

@sys.description('Location where to deploy the Key Vault.')
param location string

@sys.description('Resource Group Name where the Key Vault will be deployed.')
param resourceGroupName string

@sys.description('The name of the Key Vault to deploy.')
param keyVaultName string

@sys.description('Key Vault already exists.')
param reuseKeyVault bool



resource existingKeyVault 'Microsoft.KeyVault/vaults@2023-02-01' existing = if(reuseKeyVault) {
  scope: resourceGroup('${subscriptionId}', '${resourceGroupName}')
  name: keyVaultName
}

module wrklKeyVault '../../../../carml/1.3.0/Microsoft.KeyVault/vaults/deploy.bicep' = {
  scope: resourceGroup('${subscriptionId}', '${resourceGroupName}')
  name: 'Workload-KeyVault-${time}'
  params: {
      name: keyVaultName
      location: existingKeyVault.
      enableRbacAuthorization: false
      enablePurgeProtection: true
      softDeleteRetentionInDays: 7
      publicNetworkAccess: deployPrivateEndpointKeyvaultStorage ? 'Disabled' : 'Enabled'
      networkAcls: deployPrivateEndpointKeyvaultStorage ? {
          bypass: 'AzureServices'
          defaultAction: 'Deny'
          virtualNetworkRules: []
          ipRules: []
      } : {}
      privateEndpoints: deployPrivateEndpointKeyvaultStorage ? [
          {
              name: varWrklKvPrivateEndpointName
              subnetResourceId: createAvdVnet ? '${networking.outputs.virtualNetworkResourceId}/subnets/${varVnetPrivateEndpointSubnetName}' : existingVnetPrivateEndpointSubnetResourceId
              customNetworkInterfaceName: 'nic-01-${varWrklKvPrivateEndpointName}'
              service: 'vault'
              privateDnsZoneGroup: {
                  privateDNSResourceIds: [
                      createPrivateDnsZones ? networking.outputs.KeyVaultDnsZoneResourceId : avdVnetPrivateDnsZoneKeyvaultId
                  ]
              }
          }
      ] : []
      tags: createResourceTags ? union(varCustomResourceTags, varAvdDefaultTags) : varAvdDefaultTags

  }
  dependsOn: [
      baselineResourceGroups
      monitoringDiagnosticSettings
  ]
}

// Had to break out secrets from parent in order to keep them idempotent with the deployment of a different hostpool identity type and also the GetSecret() function only works on the Secure String Parameter type, not Secure Object type. (avoids BICEP error BCP180)
module secretDomainJoinUserName '../../../../carml/1.3.0/Microsoft.KeyVault/vaults/secrets/deploy.bicep' = {
  scope: resourceGroup('${avdsubscriptionId}', '${varresourceGroupName}')
  name: 'Workload-KeyVault-Secret-domainJoinUserName-${time}'
  params: {
      name: 'domainJoinUserName'
      keyVaultName: wrklKeyVault.name
      value: (avdIdentityServiceProvider != 'AAD') ? avdDomainJoinUserName : !empty(existingAVDWorkspaceResourceId) ? existingKeyVault.getSecret('domainJoinUserName') : 'AAD-Joined-Deployment-No-Domain-Credentials'
  }
}

module secretDomainJoinUserPassword '../../../../carml/1.3.0/Microsoft.KeyVault/vaults/secrets/deploy.bicep' = {
  scope: resourceGroup('${avdsubscriptionId}', '${varresourceGroupName}')
  name: 'Workload-KeyVault-Secret-domainJoinUserPassword-${time}'
  params: {
      name: 'domainJoinUserPassword'
      keyVaultName: wrklKeyVault.name
      value: (avdIdentityServiceProvider != 'AAD') ? avdDomainJoinUserPassword : !empty(existingAVDWorkspaceResourceId) ? existingKeyVault.getSecret('domainJoinUserPassword') : 'AAD-Joined-Deployment-No-Domain-Credentials'
  }
}

module secretVmLocalUserName '../../../../carml/1.3.0/Microsoft.KeyVault/vaults/secrets/deploy.bicep' = {
  scope: resourceGroup('${avdsubscriptionId}', '${varresourceGroupName}')
  name: 'Workload-KeyVault-Secret-vmLocalUserName-${time}'
  params: {
      name: 'vmLocalUserName'
      keyVaultName: wrklKeyVault.name
      value: avdVmLocalUserName
  }
}

module secretVmLocalUserPassword '../../../../carml/1.3.0/Microsoft.KeyVault/vaults/' = {
  scope: resourceGroup('${avdsubscriptionId}', '${varresourceGroupName}')
  name: 'Workload-KeyVault-Secret-vmLocalUserPassword-${time}'
  params: {
      name: 'vmLocalUserPassword'
      keyVaultName: wrklKeyVault.name
      value: avdVmLocalUserPassword
  }
}