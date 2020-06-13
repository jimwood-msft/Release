<#
    .SYNOPSIS
    Script for deploying a new a specified resource

    .PARAMETER ResourceGroupName
    The resource group location.

    .NOTES
        File Name    : DeployResourceSet.ps1
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
    [string] $ResourceSet,

    [parameter(Mandatory=$True)]
    [string] $ParametersFile,

    [parameter(Mandatory=$True)]
    [string] $DeploymentPriorityFile,

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
$ParametersFile = "$root\$ParametersFile"

$parametersFileObject = (Get-Content $ParametersFile) | ConvertFrom-Json

# Check if $DeploymentPriorityFile is url instead of file path.
if($DeploymentPriorityFile.StartsWith("http", "CurrentCultureIgnoreCase")) {
    try {
        Write-Host "DeploymentPriorityFile is a Url, Attempting to download."
        $randomGuid = [guid]::NewGuid().Guid
        $outputFile = "$root\PriorityConfig.$randomGuid.json"
        $response = Invoke-WebRequest -Uri $DeploymentPriorityFile -OutFile $outputFile -Method Get
        $DeploymentPriorityFile = $outputFile
    }
    catch {
        throw "Could not download file from url $DeploymentPriorityFile. - $_.Exception"
    }
}
else {
    $DeploymentPriorityFile = "$root\$DeploymentPriorityFile"
}

$ResourcesDeployed = New-Object System.Collections.ArrayList
if ($DeploymentPriorityFile) {
    #Check if the parameter file exists.
    if(Test-Path $DeploymentPriorityFile) {
        $fileContent = (Get-Content $DeploymentPriorityFile) -join " "

        #Convert the json in file to PSCustomObject
        $json = $fileContent | ConvertFrom-Json

        #Convert PSCustomObject to Hash Table
        $PriorityFileContent = $json | ConvertToHashTable
        $Resources = $PriorityFileContent.Get_Item($ResourceSet).Priority | ForEach-Object {
            $Resource = "$ResourceSet\$_"
            $Folder, $ResourceName = $Resource.Split("\")
            $TemplateFile = "$root\$Resource\$ResourceName.json"
            $TemplateParameterFile = "$root\$Resource\$ResourceName.parameters.json"
            $TemplateParameterForMultipleInstances = "$root\$Resource\$ResourceName.multipleInstances.parameters.json"

            #Check if resource has already been deployed
            if($ResourcesDeployed.Contains($ResourceName))
            {
                return
            }

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
                $MappedParams = MapARMTemplateParameters -MasterParams $MasterParams -ArmParams $TemplateParams -KeyVaultName $KeyVaultName

                #Update the ARM template parameters file with mapped parameters
                SaveJsonFile -JSON $MappedParams -File $TemplateParameterFile

                New-AzureRmResourceGroupDeployment `
                    -ResourceGroupName $ResourceGroupName `
                    -TemplateFile $TemplateFile `
                    -TemplateParameterFile $TemplateParameterFile `
                    -Verbose

            }
            $ResourcesDeployed.Add($ResourceName)

        }
    }
    else {
        throw "Deployment Priority file does not exist in the path specifed - $DeploymentPriorityFile"
    }
}
else {
    throw 'Error - Deployment Priority Config cannot be null.'
}