#Requires -Version 5

[CmdletBinding()]
Param (
    [Parameter(Mandatory)]
    [string]$AppName,

    [ValidateScript({Test-Path $_})]
    [string]$File,

    [switch]$SkipAzureBuild
)

# Import all related modules
. "$( $PSScriptRoot )\_ImportModules.ps1"

# Must stop on errors by default during deployment as it indicates a failure that needs to be resolved
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Load configuration variables
Write-Host "Loading configuration"
$ConfigPath = "$( $PSScriptRoot )\Config"
$GlobalConfig = Get-AppAzureConfig -Path $ConfigPath -Name Global | ConvertTo-Hashtable
$AppConfig = Get-AppAzureConfig -Path $ConfigPath -Type App -Name $AppName | ConvertTo-Hashtable

# Get Azure Resource Manager deployment template
$Template = Get-AppAzureTemplate -TemplateDir "$( $PSScriptRoot )\Templates" -Name $AppConfig.AppTemplate

if (!$File) {

    # Build file from source code
    Write-Host "Preparing deployment source for $( $AppConfig.AppName )"
    $SourceDir = Get-SourceCode -Repository $AppConfig.SourceRepo
    
    Write-Host "Running Tests for $( $AppConfig.AppName )"
    Test-DotNetApp -Source $SourceDir

    $File = New-DotNetAppRelease -Source $SourceDir -Project $AppConfig.Project
}

# Ensure Azure subscription and Context is ready
Set-AppAzureSetup -SubscriptionName $GlobalConfig.SubscriptionName

if ($SkipAzureBuild) {
    Write-Host "Skipping Azure build"
    $Sites = Get-AppAzureWebApps -Config $AppConfig
}
else {
    Write-Host "Building Azure resources"
    New-AppAzureResourceGroup -Name $AppConfig.AppResourceGroup -Region $GlobalConfig.DefaultRegion
    $Sites = $AppConfig.Regions | % { New-AppAzureWebAppService -Config $AppConfig -Template $Template -Region $_ }
}

# Publish the file to each site region configured for this app
$Sites | Publish-AppAzureRelease -Config $AppConfig -File $File
Write-Host "Deployment completed"