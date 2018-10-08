Set-StrictMode -Version Latest

function Test-DotNetApp {

    Param (
        [Parameter(Mandatory=$True)]
        [string]$Source,
        [string]$Project = "UnitTests"
    )

    Write-Host "Running $Project in $Source"
    $Output = Invoke-DotNetTestCommand -Project $Source\$Project

}

function New-DotNetAppRelease {

    Param (
        [Parameter(Mandatory=$True)]
        [string]$Source,

        [Parameter(Mandatory=$True)]
        [string]$Project
    )

    Write-Host "Building $Project in $Source"
    $PublishDir = Join-Path $Source "publish"
    $ProjectFile = Join-Path $Source "$($Project).csproj"

    if (Test-Path $PublishDir) {
        Remove-Item $PublishDir -Force -Recurse
    }
    $Output = Invoke-DotNetPublishCommand -Project $ProjectFile -OutputDir $PublishDir

    $FileName = Get-Date -Format "yyyyMMddHHmmss"
    $Dest = Join-Path $Source "$($FileName).zip"

    Write-Host "Creating ZIP from $PublishDir"
    Compress-Archive $PublishDir\* -DestinationPath $Dest
    Write-Host "Created ZIP at $Dest"
    Get-Item $Dest
}

function Invoke-DotNetTestCommand {

    Param (
        [Parameter(Mandatory=$True)]
        [string]$Project
    )

    dotnet test $Project | Out-Host

    if ($LastExitCode -ne 0) {
        throw "Errors encountered running test project $Project in $Source"
    }

}

function Invoke-DotNetPublishCommand {

    Param (
        [Parameter(Mandatory=$True)]
        [string]$Project,

        [string]$OutputDir
    )

    dotnet publish $Project -o $OutputDir -c Release | Out-Host

    if ($LastExitCode -ne 0) {
        throw "Errors encountered building project $Project"
    }

}
