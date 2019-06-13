[CmdletBinding()]

param(
    [Parameter(Mandatory=$True,HelpMessage='Azure resource group containing virtual machine.')]
    [string] $ResourceGroupName,

    [Parameter(Mandatory=$True,HelpMessage='The Azure virtual machine name.')]
    [string] $VirtualMachineName
)

function Get-ConnectionAzProfile
{
     # Connect to Azure AD and obtain an authorized context to access directory information regarding owner    
    [Cmdletbinding()]

    param(
        
        [Parameter(Mandatory=$False, HelpMessage='Azure connection name.')]
        [string] $ConnectionName = 'AzureRunAsConnection'
    
    )

    $OUTPUT = @{
        Result = "NotExecuted"
        Value = "None"
    }
    
    try
    {
        $servicePrincipalConnection = Get-AutomationConnection -Name $ConnectionName
        $azProfile = Add-AzAccount -ServicePrincipal `
                                   -TenantId $servicePrincipalConnection.TenantId `
                                   -ApplicationId $servicePrincipalConnection.ApplicationId `
                                   -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 3>&1 2>&1 > $null
        $OUTPUT = [PSCustomObject] @{
            Result = "Success"
            Value = $azProfile
        }
    }
    catch
    {
        if (!$servicePrincipalConnection)
        {
            try
            {
                $azContext = Get-AzContext
                $OUTPUT = [PSCustomObject] @{
                    Result = "Success"
                    Value = $azContext
                }
            }
            catch 
            {
                $OUTPUT = [PSCustomObject] @{
                    Result = "Failure"
                    Value = "No service principal connection; cannot obtain Azure context."
                }
            }
        }
        else
        {
            $OUTPUT = [PSCustomObject] @{
                Result = "Failure"
                Value = $_.Exception
            }
        }
    }
    finally
    {
        Write-Output $OUTPUT
    }
}  

function DataSensitivity {
    
    param(
        [Parameter(Mandatory=$True)]
        [HashTable] $Tags
    )

    $tagsObject = [PSCustomObject] $Tags

    if ($tagsObject.DataSensitivity) {
        [String] ($tagsObject.DataSensitivity)
    } else {
        [String] 'None'
    }
}

function VmName {
    param(
        [Parameter(Mandatory=$True)]
        [String] $VmId
    )

    if ($VmId.ToString() -eq [String]::Empty) {
        [String] 'None'
    } elseif ($VmId){
        [String] $($VmId.Split('/')[-1])
    }
}
function VnetName {
    param(
        [Parameter(Mandatory=$True)]
        [String] $SubnetId
    )

    if ($SubnetId.ToString() -eq [String]::Empty) {
        [String ]'None'
    } elseif ($SubnetId) {
        [String] $($SubnetId.Split('/')[8])
    }
}

function AzPrivateIps {
    param(
        [Parameter(Mandatory=$true)]
        $AzNetworkInterface
    )
    $azNic = $AzNetworkInterface
    $azPrivateIps = New-Object System.Collections.Generic.List[System.Object]

    #region: Checks for null; return some valid type.
    # Source of nasty errors-->Azure Commandlets will return [type]::empty or null
    $tags = if (($null -eq $nic.Tag) -or ($nic.Tag -eq {})) {
                @{ DataSensitivity = 'None' }
            } else {
                $nic.Tag
            }
    $attachedVm = if ($null -eq $azNic.VirtualMachine) {
                    [PSCustomObject]@{ Id = '/none' }
                  } else {
                    $azNic.VirtualMachine
                  }
    #endregion: Checks for null; return some valid type.

    $azNic.IpConfigurations | ForEach-Object {
        $attachedSubnet = if ($null -eq $_.Subnet) {
                              [PSCustomObject]@{
                                  Id = '/subscriptions/none/resourceGroups/none' + `
                                       '/providers/Microsoft.Network/virtualNetworks/none' + `
                                       '/subnets/none'
                               }
                          } else {
                              $_.Subnet
                          }
        $azPrivateIps.Add(
            [PSCustomObject] @{
                Address = $_.PrivateIpAddress
                Properties = [PSCustomObject] @{
                    DataSensitivity = DataSensitivity -Tags $tags
                    AttachedVmName = VmName -VmId $attachedVm.Id
                    AttachedToVnet = VnetName -SubnetId $attachedSubnet.Id
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
        [Parameter(ParameterSetName='Computer')]
        [String] $ResourceGroupName,

        [Parameter(ParameterSetName='Computer', Mandatory=$True)]
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
        'Computer' {
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

<#
Get-AzNICTags
{
    [CmdletBinding()]

    param(
        [Parameter(Mandatory=$True,HelpMessage='Azure resource group containing virtual machine.')]
        [string] $ResourceGroupName,

        [Parameter(Mandatory=$True,HelpMessage='The Azure virtual machine name.')]
        [string] $VirtualMachineName
    )

    $OUTPUT = @{
        Result = "NotExecuted"
        Value = "None"
    }

    Write-Output $OUTPUT
}
#>

Write-Output $(Get-ConnectionAzProfile | ConvertTo-Json)

