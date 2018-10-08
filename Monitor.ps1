#Requires -Version 5

[CmdletBinding()]
Param (
    [Parameter(Mandatory)]
    [string]$AppName,

    [int]$Period = 3600,

    [string[]]$Metrics = @("CpuTime","AverageResponseTime","Requests","Http2xx",,"Http4xx","Http5xx")

)

# Import all related modules
. "$( $PSScriptRoot )\_ImportModules.ps1"

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Load configuration variables
Write-Host "Loading configuration"
$ConfigPath = "$( $PSScriptRoot )\Config"
$GlobalConfig = Get-AppAzureConfig -Path $ConfigPath -Name Global | ConvertTo-Hashtable
$AppConfig = Get-AppAzureConfig -Path $ConfigPath -Type App -Name $AppName | ConvertTo-Hashtable

# Get sites from all regions in config
$Sites = Get-AppAzureWebApps -Config $AppConfig

foreach ($Site in $Sites) {

    Write-Host "Running Tests for $($Site.Name)"
    Test-AppAzureWeb -Site $Site -Tests $AppConfig.Tests -ErrorAction Continue

    Write-Host "Gathering Metrics for $($Site.Name)"
    $MetricParams = [hashtable]@{
        ResourceId = $Site.Id
        MetricName = $Metrics
        StartTime = (Get-Date).AddSeconds(-$Period)
        EndTime = (Get-Date)
        TimeGrain = (New-TimeSpan -Seconds 60)
        WarningAction = "SilentlyContinue"
    }

    $TotalTime = New-TimeSpan -Start $MetricParams.StartTime -End $MetricParams.EndTime

    Get-AzureRmMetric @MetricParams |
        Group -Property { $_.Name.LocalizedValue } |
        Select -Property Name,
        @{Name="1 Min"; Expression = {Get-MetricAggregate $_.Group -Last 1 }},
        @{Name="10 Min"; Expression = {Get-MetricAggregate $_.Group -Last 10 }},
        @{Name="$([int]$TotalTime.TotalMinutes) Min"; Expression = {Get-MetricAggregate $_.Group }}

}
