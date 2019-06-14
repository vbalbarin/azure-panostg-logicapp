$SUBSCRIPTION_NAME = (Get-AzContext).Subscription.Name

function AzDataSensitivity {
    param(
        [Parameter(Mandatory=$True)]
        [AllowNull()]
        [HashTable] $Tags
    )

    if (($Tags) -and !($Tags -eq {})) {
        $ds = $Tags.DataSensitivity
        if ($ds) {[String] $ds} else {[String] 'None'}
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