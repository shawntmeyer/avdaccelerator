targetScope = 'subscription'

// ========== //
// Parameters //
// ========== //
@description('Resource Group name for the session hosts.')
param avdComputeObjectsRgName string

@description('Optional. AVD workload subscription ID, multiple subscriptions scenario.')
param avdWorkloadSubsId string

@description('Required. Virtual machine time zone.')
param avdTimeZone string

@description('Resource Group Name for Azure Files.')
param avdStorageObjectsRgName string

@description('Required, The service providing domain services for Azure Virtual Desktop.')
param avdIdentityServiceProvider string

@description('Resource Group Name for Azure Files.')
param avdServiceObjectsRgName string

@description('Storage account files priovate endpoint name.')
param avdWrklStoragePrivateEndpointName string

@description('AVD subnet ID.')
param avdSubnetId string

@description('Optional. Create new virtual network.')
param createAvdVnet bool

@description('Required. Location where to deploy compute services.')
param avdSessionHostLocation string

@description('Optional. This property can be used by user in the request to enable or disable the Host Encryption for the virtual machine. This will enable the encryption for all the disks including Resource/Temp disk at host itself. For security reasons, it is recommended to set encryptionAtHost to True. Restrictions: Cannot be enabled if Azure Disk Encryption (guest-VM encryption using bitlocker/DM-Crypt) is enabled on your VMs.')
param encryptionAtHost bool

@description('Session host VM size.')
param avdSessionHostsSize string

@description('OS disk type for session host.')
param avdSessionHostDiskType string

@description('Market Place OS image')
param marketPlaceGalleryWindowsManagementVm object

@description('Set to deploy image from Azure. Compute Gallery')
param useSharedImage bool

@description('Source custom image ID.')
param avdImageTemplateDefinitionId string

@description('*Managed Identity Resource ID.')
param ManagedIdentityResourceId string

@description('*File share SMB multichannel.')
param avdFileShareMultichannel bool

@description('Subnet resource ID for the Azure Files private endpoint.')
param subnetResourceId string

@description('Local administrator username.')
param avdVmLocalUserName string

@description('Required. AD domain name.')
param avdIdentityDomainName string

@description('Required. Keyvault name to get credentials from.')
param avdWrklKvName string

@description('Required. AVD session host domain join credentials.')
param avdDomainJoinUserName string

@description('Optional. OU path to join AVd VMs.')
param sessionHostOuPath string

@description('Application Security Group (ASG) for the session hosts.')
param avdApplicationSecurityGroupResourceId string

@description('*Azure Files storage account name.')
param avdStorageName string

@description('*Azure Files share name.')
param avdContainerFileShareName string

@description('*Azure Files storage account SKU.')
param StorageSku string

@description('*Azure File share quota')
param avdFileShareQuotaSize int

@description('Use Azure private DNS zones for private endpoints.')
param avdVnetPrivateDnsZone bool

@description('Use Azure private DNS zones for private endpoints.')
param avdVnetPrivateDnsZoneFilesId string

@description('Name for management virtual machine. for tools and to join Azure Files to domain.')
param managementVmName string

@description('Script name for adding storage account to Active Directory.')
param storageToDomainScript string

@description('Script arguments for adding the storage account to Active Directory.')
@secure()
param storageToDomainScriptArgs string

@description('URI for the script for adding the storage account to Active Directory.')
param storageToDomainScriptUri string

@description('Required. Tags to be applied to resources')
param avdTags object

@description('Optional. Log analytics workspace for diagnostic logs.')
param avdAlaWorkspaceResourceId string

@description('Optional. Diagnostic logs retention.')
param avdDiagnosticLogsRetentionInDays int

@description('Do not modify, used to set unique value for resource deployment.')
param time string = utcNow()

param storagePurpose string

/*@description('The name being applied to the storage account')
param stName string
*/

// =========== //
// Variable declaration //
// =========== //
var varAvdFileShareLogsDiagnostic = [
    'StorageRead'
    'StorageWrite'
    'StorageDelete'
]
var varAvdFileShareMetricsDiagnostic = [
    'Transaction'
]


// =========== //
// Deployments //
// =========== //

// Call on the KV.
resource avdWrklKeyVaultget 'Microsoft.KeyVault/vaults@2021-06-01-preview' existing = {
    name: avdWrklKvName
    scope: resourceGroup('${avdWorkloadSubsId}', '${avdServiceObjectsRgName}')
}

// Provision the storage account and Azure Files.
module storageAndFile '../../../carml/1.2.0/Microsoft.Storage/storageAccounts/deploy.bicep' = {
    scope: resourceGroup('${avdWorkloadSubsId}', '${avdStorageObjectsRgName}')
    name: 'AVD-${storagePurpose}-${time}'
    params: {
        name: avdStorageName
        location: avdSessionHostLocation
        storageAccountSku: StorageSku
        allowBlobPublicAccess: false
        storageAccountKind: ((StorageSku =~ 'Premium_LRS') || (StorageSku =~ 'Premium_ZRS')) ? 'FileStorage' : 'StorageV2'
        azureFilesIdentityBasedAuthentication: (avdIdentityServiceProvider == 'AADDS') ? {
            directoryServiceOptions: 'AADDS'
        }: {
            directoryServiceOptions: 'None'
        }
        storageAccountAccessTier: 'Hot'
        networkAcls: {
            bypass: 'AzureServices'
            defaultAction: 'Deny'
            virtualNetworkRules: []
            ipRules: []
        }
        fileServices: {
            shares: [
                {
                    name: avdContainerFileShareName
                    sharedQuota: avdFileShareQuotaSize * 100 //Portal UI steps scale
                }
            ]
            protocolSettings: avdFileShareMultichannel ? {
                smb: {
                    multichannel: {
                        enabled: avdFileShareMultichannel
                    }
                }
            } : {}
            diagnosticWorkspaceId: avdAlaWorkspaceResourceId
            diagnosticLogCategoriesToEnable: varAvdFileShareLogsDiagnostic
            diagnosticMetricsToEnable: varAvdFileShareMetricsDiagnostic
        }
        privateEndpoints: avdVnetPrivateDnsZone ? [
            {
                name: avdWrklStoragePrivateEndpointName
                subnetResourceId: subnetResourceId
                service: 'file'
                privateDnsZoneResourceIds: [
                    avdVnetPrivateDnsZoneFilesId
                ]
            }
        ] : [
            {
                name: avdWrklStoragePrivateEndpointName
                subnetResourceId: subnetResourceId
                service: 'file'
            }
        ]
        tags: avdTags
        diagnosticWorkspaceId: avdAlaWorkspaceResourceId
        diagnosticLogsRetentionInDays: avdDiagnosticLogsRetentionInDays
    }
}

// Provision temporary VM and add it to domain.
//delete this..add storageaccountname?
module managementVM '../../../carml/1.2.0/Microsoft.Compute/virtualMachines/deploy.bicep' = {
    scope: resourceGroup('${avdWorkloadSubsId}', '${avdServiceObjectsRgName}')
    name: 'Deploy-Mgmt-VM-${storagePurpose}-${time}'
    params: {
        name: managementVmName
        location: avdSessionHostLocation
        timeZone: avdTimeZone
        systemAssignedIdentity: false
        userAssignedIdentities: {
            '${ManagedIdentityResourceId}': {}
        }
        encryptionAtHost: encryptionAtHost
        availabilityZone: []
        osType: 'Windows'
        //licenseType: 'Windows_Client'
        vmSize: avdSessionHostsSize
        imageReference: useSharedImage ? json('{\'id\': \'${avdImageTemplateDefinitionId}\'}') : marketPlaceGalleryWindowsManagementVm
        //imageReference: marketPlaceGalleryWindowsManagementVm
        osDisk: {
            createOption: 'fromImage'
            deleteOption: 'Delete'
            diskSizeGB: 128
            managedDisk: {
                storageAccountType: avdSessionHostDiskType
            }
        }
        adminUsername: avdVmLocalUserName
        adminPassword: avdWrklKeyVaultget.getSecret('avdVmLocalUserPassword')
        nicConfigurations: [
            {
                nicSuffix: 'nic-01-'
                deleteOption: 'Delete'
                enableAcceleratedNetworking: false
                ipConfigurations: createAvdVnet ? [
                    {
                        name: 'ipconfig01'
                        subnetId: avdSubnetId
                        applicationSecurityGroups: avdApplicationSecurityGroupResourceId
                    }
                ] : [
                    {
                        name: 'ipconfig01'
                        subnetId: avdSubnetId
                    }
                ]
            }
        ]
        // Join domain
        allowExtensionOperations: true
        extensionDomainJoinPassword: avdWrklKeyVaultget.getSecret('avdDomainJoinUserPassword')
        extensionDomainJoinConfig: {
            enabled: true
            settings: {
                name: avdIdentityDomainName
                ouPath: !empty(sessionHostOuPath) ? sessionHostOuPath : null
                user: avdDomainJoinUserName
                restart: 'true'
                options: '3'
            }
        }
        tags: avdTags
    }
    dependsOn: [
        storageAndFile
    ]
}

// Introduce delay for management VM to be ready.
module managementVmDelay '../../../carml/1.0.0/Microsoft.Resources/deploymentScripts/deploy.bicep' = {
    scope: resourceGroup('${avdWorkloadSubsId}', '${avdServiceObjectsRgName}')
    name: 'AVD-Management-VM-${storagePurpose}-Delay-${time}'
    params: {
        name: 'AVD-userManagedIdentityDelay-${time}'
        location: avdSessionHostLocation
        azPowerShellVersion: '6.2'
        cleanupPreference: 'Always'
        timeout: 'PT10M'
        scriptContent: '''
        Write-Host "Start"
        Get-Date
        Start-Sleep -Seconds 120
        Write-Host "Stop"
        Get-Date
        '''
    }
    dependsOn: [
        managementVM
    ]
} 

// Custom Extension call in on the DSC script to join Azure storage account to domain. 
module addShareToDomainScript '../../vm-custom-extensions/add-azure-files-to-domain-script.bicep' = { //if(avdIdentityServiceProvider == 'ADDS')  {
    scope: resourceGroup('${avdWorkloadSubsId}', '${avdServiceObjectsRgName}')
    name: 'Add-${storagePurpose}Storage-Setup-${time}'
    params: {
        location: avdSessionHostLocation
        name: managementVM.outputs.name
        file: storageToDomainScript
        ScriptArguments: storageToDomainScriptArgs
        baseScriptUri: storageToDomainScriptUri
    }
    dependsOn: [
        storageAndFile
        managementVmDelay
    ]
}

// Run deployment script to remove the VM --> 0.2 release. 
// needs user managed identity --> Virtual machine contributor role assignment. Deployment script to assume the identity to delete VM. Include NIC and disks (force)
