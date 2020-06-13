Function ConvertToHashTable
{
    <#
    .SYNOPSIS
        Converts a PSCustomObject to a HashTable.

    .DESCRIPTION
        Converts a PSCustomObject to HashTable, Generally used alongside ConvertFrom-Json

    .EXAMPLE
        $SomePSCustomObject | ConvertToHashTable

    .NOTES
        File Name      : Utility.psm1
        Author         : Sheik Farhan <shalfarh@microsoft.com>
        Copyright 2016 - Microsoft

    returns HashTable Object
    #>

    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline)]
        [PsCustomObject]$PSObject
    )

    Begin {

    }

    Process {
        $hashTable = @{}
        $PSObject | Get-Member -MemberType NoteProperty | ForEach-Object {
            $key = [string]$_.name
            $value = $PSObject.$key

            if($value -is [PSCustomObject]){
                $hashTable.Add($key,($value | ConvertToHashTable))
            }
            else{
                $hashTable.Add($key,$value)
            }
        }
        Write-Output $hashTable
    }
}

Function GetParameters
{
    <#
    .SYNOPSIS
        Reads a JSON Parameter file and returns a HashTable object.

    .DESCRIPTION
        Reads a JSON Parameter file and converts it using ConvertFrom-Json followed by ConvertToHashTable

    .EXAMPLE
        GetParameters -File example.file.json

    .NOTES
        File Name      : Utility.psm1
        Author         : Sheik Farhan <shalfarh@microsoft.com>
        Copyright 2016 - Microsoft

    returns HashTable Object
    #>

    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]$File
    )

    $fileContent = $null

    #Check if the parameter file exists.
    if(Test-Path $File){
        $fileContent = (Get-Content $File) -join " "
    }
    else{
        Write-Host "Specified parameter file does not exist at $File"
        return
    }

    #Convert the json in file to PSCustomObject
    $json = $fileContent | ConvertFrom-Json

    #Convert PSCustomObject to Hash Table
    $hashTable = $json | ConvertToHashTable

    #return the HashTable Object
    return $hashTable
}

Function GetParameterValueFromMasterParameterFile
{
    <#
    .SYNOPSIS
        Get parameter value from a Master parameter file.

    .DESCRIPTION
        Takes in one hashtable $masterParams and the name of the parameter $ParameterName

    .EXAMPLE
        GetParameterValueFromMasterParameterFile $masterParams $parameterName

    .NOTES
        File Name      : Utility.psm1
        Author         : anils
        Copyright 2018 - Microsoft

    returns parameter value
    #>

    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [HashTable]$MasterParams,

        [Parameter(Mandatory=$true)]
        [string]$parameterName
    )

    $flattenedMasterParams = @{}

    #Flatten the HashTable
    $MasterParams.keys | ForEach-Object {
        $MasterParamsKey = $_
        if($MasterParams.$MasterParamsKey -is [HashTable]){
            $MasterParams.$MasterParamsKey.keys | ForEach-Object {
                $flattenedMasterParams.Add($_,$MasterParams.$MasterParamsKey.$_)
            }
        }
        else{
            $flattenedMasterParams.Add($MasterParamsKey,$MasterParams.$MasterParamsKey)
        }
    }

	# Get the parameter value
	$paramValue = ""
	if ($flattenedMasterParams.keys -contains $parameterName)
	{
		return $flattenedMasterParams.$parameterName
	}
	else
	{
		return $null
    }
}

Function MapARMTemplateParameters
{
    <#
    .SYNOPSIS
        Maps ARM template parameters from a Master parameter file to parameters required by the ARM template of a resource.

    .DESCRIPTION
        Takes in two hashtables $masterParams, $armParams, and maps parameters from $masterParams to $armParams, M : N mapping, where N <= M

    .EXAMPLE
        MapARMTemplateParameters -Source $masterParams -Destination $armParams

    .NOTES
        File Name      : Utility.psm1
        Author         : Sheik Farhan <shalfarh@microsoft.com>
        Copyright 2016 - Microsoft

    returns updated $armParams
    #>

    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [HashTable]$MasterParams,

        [Parameter(Mandatory=$true)]
        [HashTable]$ArmParams,

        [Parameter(Mandatory=$false)]
        [string]$KeyVaultName
    )

    $flattenedMasterParams = @{}

    #Flatten the HashTable
    $MasterParams.keys | ForEach-Object {
        $MasterParamsKey = $_
        if($MasterParams.$MasterParamsKey -is [HashTable]){
            $MasterParams.$MasterParamsKey.keys | ForEach-Object {
                $flattenedMasterParams.Add($_,$MasterParams.$MasterParamsKey.$_)
            }
        }
        else{
            $flattenedMasterParams.Add($MasterParamsKey,$MasterParams.$MasterParamsKey)
        }
    }

    #Map the values
    $ArmParams.parameters.keys | ForEach-Object {
        if($flattenedMasterParams.$_ -eq $false -or $flattenedMasterParams.$_)
        {
            # If the value of the parameter starts with "~", fetch the value from key vault.
		    if ($flattenedMasterParams.$_.value -match "PULLEDFROMKEYVAULT")
		    {
			    $name = $flattenedMasterParams.$_.secretName
			    $value = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $name).SecretValueText
			    $ArmParams.parameters.$_.value = $value
		    }
            Else
            {
                $ArmParams.parameters.$_.value = $flattenedMasterParams.$_
            }
        }
        else{
            throw "$_ parameter is present in ARM template parameters file but not in consolodiated Parameters file. Make sure all parameters required by ARM template are present in consolidated Parameters file (Default: Parameters.json)."
        }
    }

    #Return the HashTable Object
    return $ArmParams
}

Function SaveJsonFile
{
    <#
    .SYNOPSIS
        Save a HashTable object as JSON into a file.

    .DESCRIPTION
        Converts a HashTable object as JSON and saves it in a file.

    .EXAMPLE
        SaveJsonFile -Json $json -File $filePath

    .NOTES
        File Name      : Utility.psm1
        Author         : Sheik Farhan <shalfarh@microsoft.com>
        Copyright 2016 - Microsoft

    returns none
    #>

    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [HashTable]$JSON,

        [Parameter(Mandatory=$true)]
        [string]$File
    )

    $JSON | ConvertTo-Json -Depth 10 | Out-File $File
}

Function Get-AzureRmCachedAccessToken()
{
    <#
    .SYNOPSIS
        Returns token for the logged-in principal

    .DESCRIPTION
        Returns token for the logged-in principal. This function was downloaded from microsoft.com.

    .EXAMPLE
        Get-AzureRmCachedAccessToken

    .NOTES
        File Name      : Utility.psm1
        Author         : anils
        Copyright 2018 - Microsoft

    returns access token
    #>
	
  $ErrorActionPreference = 'Stop'
  
  if(-not (Get-Module AzureRm.Profile)) {
    Import-Module AzureRm.Profile
  }
  $azureRmProfileModuleVersion = (Get-Module AzureRm.Profile).Version
  # refactoring performed in AzureRm.Profile v3.0 or later
  if($azureRmProfileModuleVersion.Major -ge 3) {
    $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
    if(-not $azureRmProfile.Accounts.Count) {
      Write-Error "Ensure you have logged in before calling this function."    
    }
  } else {
    # AzureRm.Profile < v3.0
    $azureRmProfile = [Microsoft.WindowsAzure.Commands.Common.AzureRmProfileProvider]::Instance.Profile
    if(-not $azureRmProfile.Context.Account.Count) {
      Write-Error "Ensure you have logged in before calling this function."    
    }
  }
  
  $currentAzureContext = Get-AzureRmContext
  $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile)
  Write-Debug ("Getting access token for tenant" + $currentAzureContext.Subscription.TenantId)
  $token = $profileClient.AcquireAccessToken($currentAzureContext.Subscription.TenantId)
  $token.AccessToken
}

Function Get-LogicAppConnections()
{
	[CmdLetBinding()]
	param
	(
		[parameter(Mandatory=$True)]
		[string] $ResourceGroupName,

		[parameter(Mandatory=$True)]
		[string] $ConnectionType,

		[parameter(Mandatory=$True)]
		[string] $Connections
	)

	if ($Local:BuildOutputPath)
	{
		$Script:ModuleRoot = Join-Path -Path $Local:BuildOutputPath -ChildPath "Release"
	}
	else
	{
		# Note: Load from the same folder as this script is running from.
		$Script:ModuleRoot = Join-Path -Path $Script:PSScriptRoot -ChildPath ""
	}

	$null = Import-Module -Name (Join-Path -Path $Script:ModuleRoot -ChildPath "Deployment") -Force -DisableNameChecking

	#### Get the definition of the logic app
	$subscriptionId = (Get-AzureRmResourceGroup -Name $ResourceGroupName).ResourceId.split('/')[2]

	$logicAppConnections = @{};

	# Get resource group location
	$resourceGroupLocation = (Get-AzureRmResourceGroup -Name $ResourceGroupName).Location

	# Loop thru all the parameter collections
	$connectionList = $Connections -split ","
	$connectionList | ForEach-Object {

		$connectionName = $_.ToString().Trim()

		# Connection does not exist in logic app, create one
		$parameter =  @{
			"connectionId" = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/connections/$connectionName"
			"connectionName" = "$connectionName"
			"id" = "/subscriptions/$subscriptionId/providers/Microsoft.Web/locations/$resourceGroupLocation/managedApis/$ConnectionType"
		}
		$logicAppConnections | Add-Member -MemberType NoteProperty -Name "$connectionName" -Value $parameter
	}

	return $logicAppConnections | ConvertTo-Json -Depth 10
}