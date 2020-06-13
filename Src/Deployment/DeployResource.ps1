<#
    .SYNOPSIS
    Script for deploying a new specified resource

    .PARAMETER ResourceGroupName
    The resource group name.

    .PARAMETER Resource
    The resource to deploy (ex. "LogicApps\TestLogicApp").

    .PARAMETER $ParametersFile
    The parameters file (ex. "Properties\Parameters.json").

    .NOTES
        File Name    : DeployResource.ps1
        Author       : Sheik Farhan <shalfarh@microsoft.com>
        Prerequisite : PowerShell V3 or more.
        Copyright 2016 - Microsoft
#>
[CmdLetBinding()]
param
(
    [parameter(Mandatory=$True)]
    [string] $SubscriptionID,

    [parameter(Mandatory=$True)] 
    [string] $ResourceGroupName,

    [parameter(Mandatory=$True)]
    [string] $Resource,

    [parameter(Mandatory=$True)]
    [string] $ParametersFile,

    [parameter(Mandatory=$False)]
    [string] $KeyVaultName
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

try
{
    Select-AzureRmSubscription -Subscription $SubscriptionID -ErrorAction Stop
}
catch [System.Management.Automation.PSInvalidOperationException]
{
    Write-Host "Logging in"
    Connect-AzureRmAccount
	
    Select-AzureRmSubscription -Subscription $SubscriptionID
}

# Import deployment module.
Get-ChildItem -Path $Script:ModuleRoot | ForEach{
    If($_.Name -match ".psm1")
    {
        Import-Module -Name $_.FullName -Force -DisableNameChecking
    }
}

$root = split-path $SCRIPT:MyInvocation.MyCommand.Path -parent

If($Resource.IndexOf("\") -gt 0)
{
    $Folder, $ResourceName = $Resource.Split("\")
}
Else
{
    $Folder = $Resource
    $ResourceName = $Resource
}
$TemplateFile = "$root\$Resource\$ResourceName.json"
$TemplateParameterFile = "$root\$Resource\$ResourceName.parameters.json"
$TemplateParameterForMultipleInstances = "$root\$Resource\$ResourceName.multipleInstances.parameters.json"

$ParametersFile = "$root\$ParametersFile"

$parametersFileObject = (Get-Content $ParametersFile) | ConvertFrom-Json

# If a file with format <<ResourceName>>.multipleInstances.parameters.json exist, deploy multiple instances of the same resource
if (Test-Path $TemplateParameterForMultipleInstances)
{
    $fileContent = Get-Content $TemplateParameterForMultipleInstances

    #Convert the json in file to PSCustomObject
    $fileContentjson = $fileContent | ConvertFrom-Json

    #Read Master.Params.json
    $MasterParams = GetParameters -File $ParametersFile

    # Loop thru all the parameter collections
    $fileContentjson.ParameterCollections | ForEach-Object {
        $parameters = $_ | ConvertToHashTable

        # Populate value of parameter from master parameters file (parameters.json or release variables)
        foreach ($parameter in @($parameters.Keys)) 
        {
			# If the value of the parameter starts with "!", fetch the value from deployment/release variables
            if ($parameters.$parameter.GetType() -eq [string] -and ($parameters.$parameter.startsWith("!")))
            {
                $name = ($parameters.$parameter).SubString(1)
                $value = GetParameterValueFromMasterParameterFile $MasterParams $name
                $parameters.$parameter = $value
            }

			# If the value of the parameter starts with "~", fetch the value from key vault.
            if ($parameters.$parameter.GetType() -eq [string] -and ($parameters.$parameter.startsWith("~")))
			{
				$name = ($parameters.$parameter).SubString(1)
				$value = (Get-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $name).SecretValueText
                $parameters.$parameter = $value
			}
        }

        #Read params file for resource
        $TemplateParams = GetParameters -File $TemplateParameterFile

        #Map template parameters
        $MappedParams = MapARMTemplateParameters -MasterParams $parameters -ArmParams $TemplateParams

        #Update the ARM template parameters file with mapped parameters
        SaveJsonFile -JSON $MappedParams -File $TemplateParameterFile

        # Deploy
        New-AzureRmResourceGroupDeployment `
            -ResourceGroupName $ResourceGroupName `
            -TemplateFile $TemplateFile `
            -TemplateParameterFile $TemplateParameterFile `
            -Verbose
    }
}
else
{
    #Read Master.Params.json
    $MasterParams = GetParameters -File $ParametersFile

    #Read params file for resource
    $TemplateParams = GetParameters -File $TemplateParameterFile

    #Map template parameters
    $MappedParams = MapARMTemplateParameters -MasterParams $MasterParams -ArmParams $TemplateParams

    #Update the ARM template parameters file with mapped parameters
    SaveJsonFile -JSON $MappedParams -File $TemplateParameterFile

    New-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
                                        -TemplateFile $TemplateFile `
                                        -TemplateParameterFile $TemplateParameterFile `
                                        -Verbose
}