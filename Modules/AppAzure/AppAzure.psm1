#Requires -Version 5
#Requires -Modules AzureRM.Profile
#Requires -Modules AzureRM.Websites
#Requires -Modules AzureRM.Resources
#Requires -Modules AzureRM.Insights
#Requires -Modules Utils

Set-StrictMode -Version Latest

# These functions should always stop on error as it indicates a
# problem that needs to be resolved
$ErrorActionPreference = "Stop"

function Set-AppAzureSetup
{

    Param (
        [Parameter(Mandatory)]
        [string]$SubscriptionName
    )

    $Context = Get-AzureRmContext #-ErrorAction SilentlyContinue
    if (!$Context -or !$Context.Account -or !$?) {
        Write-Error "Azure context is required, please use Connect-AzureRmAccount cmdlet to login"
    }

    Set-AzureRmContext -Subscription $SubscriptionName -ErrorAction Continue
    if (!$?) {
        Write-Error "Error setting Azure context with $SubscriptionName"
    }

}

function Get-AppAzureConfig
{

    [OutputType([pscustomobject])]
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory, ValueFromPipeLine, Position=0)]
        [string]$Path,

        [ValidateNotNullOrEmpty()]
        [string]$Type,

        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    Process {

        $FilterPrefix = if ($Name) {"$Name"}
        $FilterPrefix += if ($Type) {".$Type"}
        $FilterPrefix += if (!$FilterPrefix) {"*"}
        $Filter = "$FilterPrefix.json"

        $Files = Get-ChildItem -Path $Path -Filter $Filter
        if (!$Files) {
            Write-Error "Could not find Config using filter $Filter in $Path"
        }

        $Files | Get-Item | Get-Content -Raw | ConvertFrom-Json
    }

}

function Get-AppAzureTemplate
{

    [OutputType([System.IO.FileInfo])]
    Param (
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$TemplateDir
    )

    Process {

        $Template = Get-ChildItem $TemplateDir -Filter "*.json" | Where-Object { $_.Name -eq "$( $Name ).json" }

        if (!$Template)
        {
            Write-Error "Could not find Template with name $Name"
        }

        $Template
    }

}

function Get-AppAzureTemplateParams
{

    [OutputType([string[]])]
    Param (
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$Template
    )

    Process {

        $Template | Get-Content -Raw | ConvertFrom-Json |
                Select -ExpandProperty parameters |
                Get-Member -MemberType NoteProperty | Select -ExpandProperty Name
    }

}

function Publish-AppAzureRelease
{

    Param (
        [Parameter(Mandatory, ValueFromPipeLine)]
        [Microsoft.Azure.Management.WebSites.Models.Site]$Site,

        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [ValidateScript({Test-Path $_})]
        [string]$File,

        [Alias("SourceSlot")]
        [string]$SourceSlotName = "staging",

        [Alias("DestSlot", "DestinationSlotName")]
        [string]$DestSlotName = "production"
    )

    Process {

        $SourceSlot = Get-AzureRmWebAppSlot -WebApp $Site -Slot $SourceSlotName
        Push-AppAzureRelease -File $File -Site $SourceSlot

        # Run tests on source slot
        Write-Host "Running tests on $( $Site.Name ) for slot $SourceSlotName"
        Test-AppAzureWeb -Site $SourceSlot -Tests $Config.Tests -ErrorAction Stop

        $SwitchParams = @{
            DestinationSlotName = $DestSlotName
            SourceSlotName = $SourceSlotName
            WebApp = $Site
        }

        # Perform a "soft" switch, copying the config settings from the destination slot into the source slot
        Write-Host "Performing soft-switch from $SourceSlotName to $DestSlotName on $( $Site.Name )"
        Switch-AzureRmWebAppSlot @SwitchParams -SwapWithPreviewAction ApplySlotConfig

        # Run tests on source slot with new config settings
        Write-Host "Running tests on $( $Site.Name ) for slot $SourceSlotName with $DestSlotName configuration"
        try
        {
            Test-AppAzureWeb -Site $SourceSlot -Tests $Config.Tests -ErrorAction Stop
        }
        catch
        {
            Write-Host $_ -ForegroundColor Red
            # Something went wrong, reset the swap and restore the slot configuration
            Write-Host "Resetting soft-switch from $SourceSlotName to $DestSlotName on $( $Site.Name )"
            Switch-AzureRmWebAppSlot @SwitchParams -SwapWithPreviewAction ResetSlotSwap
            throw "Tests failed after soft switch. Slot switch was reset and publishing aborted."
        }

        Write-Host "Completing switch from $SourceSlotName to $DestSlotName on $( $Site.Name )"
        Switch-AzureRmWebAppSlot @SwitchParams -SwapWithPreviewAction CompleteSlotSwap

        if ($DestSlotName -ieq "production")
        {
            $DestSlot = $Site
        }
        else
        {
            $DestSlot = Get-AzureRmWebAppSlot -WebApp $Site -Slot $DestSlotName
        }

        # Run tests on destination slot after swap completed
        Write-Host "Running tests on $( $Site.Name ) for slot $DestSlotName"
        try
        {
            Test-AppAzureWeb -Site $DestSlot -Tests $Config.Tests -ErrorAction Stop
        }
        catch
        {
            Write-Host $_ -ForegroundColor Red
            # Something went wrong, swap back to the original slot
            Write-Host "Swapping back slots from $DestSlotName to $SourceSlotName on $( $Site.Name )"
            Switch-AzureRmWebAppSlot @SwitchParams

            # Run tests again on the destination slot, hopefully all ok now
            Write-Host "Re-running tests on $( $Site.Name ) for slot $DestSlotName (restored)"
            Test-AppAzureWeb -Site $DestSlot -Tests $Config.Tests -ErrorAction Continue

            throw "Tests failed after switch. Slot switch was backed out and publishing aborted."
        }

        Write-Host "Successfully published $SourceSlotName to $DestSlotName on $( $Site.Name )"

    }

}

function Push-AppAzureRelease
{
    Param (
        [Parameter(Mandatory, ValueFromPipeLine)]
        [Microsoft.Azure.Management.WebSites.Models.Site]$Site,

        [Parameter(Mandatory)]
        [string]$File
    )

    $FileInfo = Get-Item $File

    Write-Host "Deploying $( $FileInfo.Name ) to $( $Site.Name )"

    $Uri = "https://$($Site.DefaultHostName)/api/zipdeploy".ToLower() -replace ".azurewebsites.net",".scm.azurewebsites.net"

    # Details of accessing deployment credentials for Kudu API can be found here:
    # https://github.com/projectkudu/kudu/wiki/REST-API
    $Credentials = Invoke-AzureRmResourceAction -ResourceGroupName $Site.ResourceGroup -ResourceType "$( $Site.Type )/config" -ResourceName "$( $Site.Name )/publishingcredentials" -Action list -ApiVersion 2018-02-01 -Force
    $Username = $Credentials.Properties.publishingUserName
    $Password = $Credentials.Properties.publishingPassword

    $Base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $Username, $Password)))

    $Result = Invoke-RestMethod -Uri $Uri -Headers @{ Authorization = ("Basic $Base64AuthInfo") } -Method POST -InFile $FileInfo.FullName -ContentType "multipart/form-data"

}

function New-AppAzureResourceGroup
{
    Param (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Region
    )

    if ((Get-AzureRmResourceGroup -Name $Name -Location $Region -ErrorAction SilentlyContinue) -eq $null)
    {
        Write-Host "Creating Resource Group $Name in $Region"
        New-AzureRmResourceGroup -Name $Name -Location $Region -Force
    }
    else
    {
        Write-Host "Resource Group $Name already exists"
    }
}

function Get-AppAzureWebApps
{
    [OutputType([Microsoft.Azure.Management.WebSites.Models.Site[]])]
    Param (
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    Get-AzureRmWebApp -ResourceGroupName $Config.AppResourceGroup | Where { $_.Name -match "^$( $Config.AppName )-" -and $Config.Regions -contains $_.Location }
}

function New-AppAzureWebAppService
{

    [OutputType([Microsoft.Azure.Management.WebSites.Models.Site[]])]
    Param (
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [System.IO.FileInfo]$Template,

        [Parameter(Mandatory)]
        [string]$Region
    )

    $TemplateParams = @{
        Region = $Region
    }

    Write-Host "Creating Web App Service for $( $Config.AppName ) in $Region"
    New-AppAzureResourceGroupDeployment -Config $Config -TemplateParams $TemplateParams -Template $Template

    Get-AzureRmWebApp -ResourceGroupName $Config.AppResourceGroup | Where { $_.Name -match "^$( $Config.AppName )-" -and $_.Location -eq $Region }

}

function New-AppAzureResourceGroupDeployment
{

    Param (
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [System.IO.FileInfo]$Template,

        [hashtable]$TemplateParams
    )

    $ParamList = Get-AppAzureTemplateParams $Template

    $GroupDeploymentTemplateParams = Merge-Hashtable $Config $TemplateParams | Limit-HashtableKey -Keys $ParamList

    $GroupDeploymentParams = @{
        Name = "$( $Config.AppName )GroupDeployment"
        ResourceGroupName = $Config.AppResourceGroup
        TemplateFile = $Template.FullName
        TemplateParameterObject = $GroupDeploymentTemplateParams
    }

    Write-Host "Testing Resource Group Template for $( $Config.AppName )"
    $TestGroupDeployment = $GroupDeploymentParams | Remove-HashtableKey -Key Name
    $Result = Test-AzureRmResourceGroupDeployment @TestGroupDeployment
    if ($Result)
    {
        Write-Error $Result.Message
    }

    Write-Host "Executing Resource Group Template for $( $Config.AppName )"
    New-AzureRmResourceGroupDeployment @GroupDeploymentParams | Out-Null

}

function Test-AppAzureWeb {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName = $True)]
        [Alias("WebApp")]
        [Microsoft.Azure.Management.WebSites.Models.Site]$Site,

        [Parameter(Mandatory)]
        [pscustomobject[]]$Tests
    )

    Process {
        $Tests | Test-AppAzureWebApiEndPoint -Site $Site
    }
}

function Test-AppAzureWebApiEndPoint {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName = $True)]
        [Alias("WebApp")]
        [Microsoft.Azure.Management.WebSites.Models.Site]$Site,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName = $True)]
        [string]$EndPoint,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName = $True)]
        $Expects,

        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [string]$Method = "GET"
    )

    Begin {
        # PowerShell uses TLS 1.0 by default which is now deprecated
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }

    Process {

        $Uri = "https://" + $Site.DefaultHostName + "/" + $EndPoint.TrimStart("/")
        Test-ApiEndPoint $Uri -Expects $Expects -Method $Method
    }
}

function Test-ApiEndPoint
{
    [CmdletBinding(DefaultParameterSetName="SiteAndEndPoint")]
    Param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName = $True, Position=0)]
        [Alias("Url")]
        [string]$Uri,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName = $True)]
        $Expects,

        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [string]$Method = "GET"
    )

    Begin {
        # PowerShell uses TLS 1.0 by default which is now deprecated
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }

    Process {

        $TestErrorMessage = "Test Failed: $Method $Uri`nExpecting {0} but received {1}"
        $TestSuccessMessage = "Test Success: $Method $Uri"

        $Result = Invoke-RestMethod -Method $Method -Uri $Uri -ErrorAction Continue

        if (!$?) {
            Write-Error ($TestErrorMessage -f "success response", "failure")
            return
        }

        if (!$Result -and -not($Null -eq $Expects)) {
            Write-Error ($TestErrorMessage -f "a response", "nothing")
            return
        }

        if (!($Result.GetType() -eq $Expects.GetType()))
        {
            Write-Error ($TestErrorMessage -f $Expects.GetType(),$Result.GetType())
            return
        }

        if ($Result -is [array])
        {
            if ((Compare-Object $Result $Expects | Measure | Select -ExpandProperty Count) -ne 0)
            {
                Write-Error ($TestErrorMessage -f $Expects, $Result)
                return
            }
            Write-Host $TestSuccessMessage -ForegroundColor Green
            return
        }

        if ($Result -is [string])
        {
            if (!($Result -eq $Expects))
            {
                Write-Error ($TestErrorMessage -f $Expects, $Result)
                return
            }
            Write-Host $TestSuccessMessage -ForegroundColor Green
            return
        }

        if ($Result -is [pscustomobject])
        {
            if ((Compare-Object $Result.PsObject.Properties $Expects.PsObject.Properties |
                    Measure | Select -ExpandProperty Count) -ne 0)
            {
                Write-Error ($TestErrorMessage -f $Expects, $Result)
                return
            }
            Write-Host $TestSuccessMessage -ForegroundColor Green
            return
        }

        Write-Error "UNKNOWN TYPE???"

        Write-Host $TestSuccessMessage -ForegroundColor Green
    }

}

function Get-SourceCode
{
    [OutputType([System.IO.DirectoryInfo])]
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory,ParameterSetName="git")]
        [string]$Repository,

        [Parameter(Mandatory,ParameterSetName="folder")]
        [ValidateScript({Test-Path $_ -PathType Container})]
        [string]$Source
    )

    Process {

        $DeployDir = Join-Path $env:TEMP "AppAzureDeploy"
        New-Item $DeployDir -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

        # Clean up build directory
        Get-ChildItem $DeployDir -Force -Directory | Where { $_.CreationTime -lt (Get-Date).AddDays(-2)} | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

        $Random = Get-RandomString -Length 8
        $DeployDir = Join-Path $DeployDir $Random

        Write-Host "Using deployment folder $DeployDir"

        if ($PSCmdlet.ParameterSetName -eq "git") {
            New-GitClone -Repository $Repository -Destination $DeployDir | Out-Null
        }
        else {
            Write-Host "Copying from $Source to $DeployDir"
            New-Item $DeployDir -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
            Copy-Item $Source\* -Destination $DeployDir -Force -Recurse | Out-Null
        }

        Get-Item $DeployDir
    }

}

function Format-MetricAggregate {
    Param(
        [Parameter(Mandatory,ValueFromPipeline)]
        $Value,
        [string]$Type = "Sum"
    )

    Process {
        if ($Value -is [Microsoft.PowerShell.Commands.GenericMeasureInfo]) {
            $Value = ($Value.$Type)
        }
        $Format = if ($Type -eq "Average") {"0.###"} else {"0"}
        $Value.ToString($Format)
    }

}

function Get-MetricAggregate {
    Param(
        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        $Metric,

        [int]$Last
    )

    Process {

        $Data = $Metric.Data

        if ($Last) {
            $Data = $Data | Select -Last $Last
        }

        $Data | Select -ExpandProperty Total |
                Measure-Object -Average -Sum |
                Format-MetricAggregate -Type (Get-MetricAggregateType $Metric.Name.Value)

    }

}

function Get-MetricAggregateType {
    Param(
        [Parameter(Mandatory,ValueFromPipeline,Position=0)]
        $Name
    )

    Begin {
        [hashtable]$MetricAggregate = @{
            CpuTime = "Sum"
            AverageResponseTime = "Average"
            Requests = "Sum"
            Http2xx = "Sum"
            Http4xx = "Sum"
            Http5xx = "Sum"
        }
    }

    Process {
        if ($Name -is [Microsoft.Azure.Commands.Insights.OutputClasses.PSMetric]) {
            $Name = ($Name.Name.Value)
        }
        if (!$MetricAggregate.ContainsKey($Name)) {
            Write-Warning "Metric Aggregate Type not defined for $Name"
            return "Sum"
        }
        $MetricAggregate.$Name
    }
}
