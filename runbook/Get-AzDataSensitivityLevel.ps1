<#
.SYNOPSIS 
    This Automation runbook integrates with Azure event grid subscriptions to get notified when a 
    write (Create/Modification) command is performed against an Azure VM and to provide IP address
    group configurations to Palo Alto Network virtual appliances.
    
    
.DESCRIPTION
    This Automation runbook integrates with Azure event grid subscriptions to get notified when a 
    write (Create/Modification) command is performed against an Azure VM and to provide IP address
    group configurations to Palo Alto Network virtual appliances.
    
    The runbook reads the `DataSensitivity` resource tag on an Azure VM. This tag can comprise the values
    ['High', 'Medium', 'Low', 'None']. The runbook retrieves the Azure private IP addresses associated
    with any attached network interfaces. It then places the IP address into one of 4 blob storage endpoints
    corresponding to the value of the `DataSensitivity` tag. If the tag is nonexistent, the IP address
    is written to the storage blob endpoint corresponding to 'None'.

    It is possible that a VM may contain multiple network interfaces with separate private ip addresses.
    These network interfaces may possess DataSensitivity tags different from the vm.
    The code enforces the policy that all ip addresses associated with a VM be categorized with the value
    of the VM.

    TODO: Retag the NICS

    The Palo Alto network virtual appliance must be configured to retrieve the address groups from the storage blob endpoints.
    
    A RunAs account in the Automation account is required for this runbook.

.PARAMETER WebhookData
    Optional. The information about the write event that is sent to this runbook from Azure Event grid.
  
.PARAMETER ChannelURL
    Optional. The Microsoft Teams Channel webhook URL that information will get sent.

.NOTES
    AUTHOR: Vincent Balbarin
    COPYRIGHT: Yale University 2019
    LASTEDIT: 2019-07-25
#>
 
param(
    [parameter (Mandatory=$False)]
    [object] $WebhookData,

    [parameter (Mandatory=$False)]
    [String] $ChannelURL
)

$requestBody = $WebhookData.RequestBody | ConvertFrom-Json
$data = $requestBody.data

#region : PSAzureProfile
# Connect to Azure AD and obtain an authorized context to access directory information regarding owner
# and (in the future) access a blob storage container without a SAS token or storage account key
try {
    $connectionName = "AzureRunAsConnection"
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName

    Add-AzAccount -ServicePrincipal `
                  -TenantId $servicePrincipalConnection.TenantId `
                  -ApplicationId $servicePrincipalConnection.ApplicationId `
                  -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 3>&1 2>&1 > $null
} catch {
    if (!$servicePrincipalConnection) {
        $errorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}
#endregion : PSAzureProfile

#region : functions
function AzDataSensitivity {
    param(
        [Parameter(Mandatory=$True)]
        [AllowNull()]
        [HashTable] $Tags
    )

    if (($Tags) -and !($Tags -eq {})) {
        $ds = $Tags.DataSensitivity
        if ($ds) {[String] $ds} else {[String] 'None'}
    } elseif (!($Tags.ContainsKey('DataSensitivity'))) {
        [String] 'None'
    } else {
        [String] 'None'
    }
}

function AzVmName {
    param(
        [Parameter(Mandatory=$True)]
        [AllowNull()]
        [Object] $Vm
    )
    
    if ($Vm) {
        # TODO: Perhaps throw execption if `$<Parameter>` does not have `<member>`. 
        $vmId = $Vm.Id
        if (($vmId) -and !($vmId -eq [String]::Empty)) {   
            [String] $($vmId.Split('/')[-1])
        } else {
            [String] 'None'
        }
    } else {
        [String] 'None'
    }
}

function AzVnetName {
    param(
        [Parameter(Mandatory=$True)]
        [AllowNull()]
        [Object] $Subnet
    )

    if ($Subnet) {
        # TODO: Perhaps throw execption if `$<Parameter>` does not have `<member>`. 
        $subnetId = $Subnet.Id
        if (($subnetId) -and !($subnetId -eq [String]::Empty)) {   
            [String] $($SubnetId.Split('/')[8])
        } else {
            [String] 'None'
        }
    } else {
        [String] 'None'
    }
}

function AzPrivateIps {
    param(
        [Parameter(Mandatory=$true)]
        $AzNetworkInterface
    )
    $azNic = $AzNetworkInterface
    $azPrivateIps = New-Object System.Collections.Generic.List[System.Object]

    $tags = $azNic.Tag
    $attachedVm = $azNic.VirtualMachine
 
    $azNic.IpConfigurations | ForEach-Object {
        $attachedSubnet = $_.Subnet
        $azPrivateIps.Add(
            [PSCustomObject] @{
                Address = $_.PrivateIpAddress
                Properties = [PSCustomObject] @{
                    DataSensitivity = AzDataSensitivity -Tags $tags
                    AttachedVmName = AzVmName -Vm $attachedVm
                    AttachedToVnet = AzVnetName -Subnet $attachedSubnet
                }
            }
        )
    }
    $azPrivateIps.ToArray()
}

function Get-AzPrivateIps {
    [CmdletBinding()]

    param(
        [Parameter(ParameterSetName='Subscription', Mandatory=$False)]
        [Switch] $Subscription,

        [Parameter(ParameterSetName='ResourceGroup', Mandatory=$True)]
        [Parameter(ParameterSetName='VirtualMachine')]
        [String] $ResourceGroupName,

        [Parameter(ParameterSetName='VirtualMachine', Mandatory=$True)]
        [Alias('Name')]
        [String] $VirtualMachineName
    )
    
    $output = @{
        Result = 'NotExecuted'
        Value = 'None'
    }


    switch($PSCmdlet.ParameterSetName) {
        'Subscription' {
            Write-Verbose -Message ("Retrieving IP addresses in subscription {0}." -f $SUBSCRIPTION_NAME)
            $nics = Get-AzNetworkInterface
        }
        'ResourceGroup' {
            Write-Verbose -Message ("Retrieving IP addresses in resource group {0} in subscription {1}." -f $ResourceGroupName, $SUBSCRIPTION_NAME)
            $nics = (Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName)
        }
        'VirtualMachine' {
            Write-Verbose -Message ("Retrieving IP addresses for virtual machine {0} in resource group {1} in subscription {2}." -f $VirtualMachineName, $ResourceGroupName, $SUBSCRIPTION_NAME)
            $nics = (Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName | 
                    Where-Object {$_.VirtualMachine.Id.Split('/')[-1] -ieq $VirtualMachineName})
        }
    }

    $ips = New-Object System.Collections.Generic.List[System.Object]
    $nics | ForEach-Object {
        AzPrivateIps -AzNetworkInterface $_ | ForEach-Object {$ips.Add($_)}
    }
    
    $output = @{
        Result = 'Success'
        Value = $ips.ToArray()
    }

    Write-Output [PScustomObject] $output
}

function Get-AzResourceFromURI {
    [CmdletBinding()]

    param(
        [parameter(Mandatory=$True)]
        [String] $ResourceURI
    )

    # TODO: Validation?
    $azResource = @{}
    $elements = $ResourceURI.Split('/')

    $azResource = @{
        SubscriptionId = $elements[2]
        ResourceGroupName = $elements[4]
        Providers = $elements[6]
        Type = $elements[7]
        Name = $elements[8]
    }

    [PSCustomObject] $azResource
}

function DottedOctalIP {
    param(
        [parameter(Mandatory=$True)]
        [String] $DottedDecimalIP
    )

    $decimalOctets = $DottedDecimalIP.Split('.')
    $octalOctets = New-Object System.Collections.Generic.List[System.Object]
    $decimalOctets | ForEach-Object {
        $octalOctets.Add([Convert]::ToString([Int16] $_, 8).PadLeft(4, '0'))
    }
    Write-Output ($octalOctets -join '.')
}
#endregion : functions

#region : Main
$createdBy = $data.claims.'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn'
$eventTime = $requestBody.eventTime
$eventEpochTime = ([datetime] $eventTime).Subtract($(Get-Date -Date '01/01/1970')).TotalSeconds

if(!($data.operationName -match "Microsoft.Compute/virtualMachines/write" -and $data.status -match "Succeeded")) {
    Write-Error "Could not find VM write event"
} else {
    $azResource = Get-AzResourceFromURI -ResourceURI $data.resourceUri
    
    $params = @{
        ResourceGroupName = $azResource.ResourceGroupName
        Name = $azResource.Name
    }

    $vm = Get-AzVm @params

    $DataSensitivity = AzDataSensitivity -Tags $vm.Tags

    $panIpAddresses = New-Object System.Collections.Generic.List[System.Object]
    $(Get-AzPrivateIps @params).Value | ForEach-Object {
        $panIpAddresses.Add(
            @{
                $_.Address = @{
                    DataSensitivity = $DataSensitivity
                    Time = $eventEpochTime
                    ModifiedBy = $createdBy
                }
            }
        )
    }

    #region : Teams
    if (!([string]::IsNullOrEmpty($ChannelURL))) {
        # A Teams channel has been specified.
        $cardTime = $eventTime -replace '\.\d+Z', 'Z' # truncate fractional seconds
        $targetURL = 'https://portal.azure.com/#resource{0}/overview' -f $data.ResourceUri
        $messageBody = @{
            title = 'Azure Virtual Machine Notification' 
            text = 'An Azure virtual machine has been created or modified'
            sections = @(
                @{
                    activityTitle = 'Azure VM'
                    activitySubtitle = $azResource.Name
                    activityText = $(
                        'A virtual machine **{0}** [DataSensitivity = {1}] was created or modifed in the subscription **{2}** in resource group **{3}** by {4} at {{{{TIME({5})}}}}.' `
                        -f ($azResource.Name, $DataSensitivity, $azResource.SubscriptionId, $azResource.ResourceGroupName, $createdBy, $cardTime)
                    )
                    activityImage = 'https://azure.microsoft.com/svghandler/automation/'
                }
            )
            potentialAction = @(
                @{
                    '@context' = 'http://schema.org'
                    '@type' = 'ViewAction'
                    name = 'Click here to view the changes.'
                    target = @($targetURL)
                }
            )
        }
        $body = $messageBody | ConvertTo-Json -Depth 4
        Invoke-RestMethod -Method 'POST' -Uri $ChannelURL -Headers @{'Content-Type' = 'application/json'} -Body $body | Write-Verbose             
    }
    #endregion : Teams

    # Write-Output $panIpAddresses # Final commandlet output for processing in next pipeline step.
    $panIpAddresses | ForEach-Object { Write-Output $_ }
}
#endregion : Main
