Set-StrictMode -Version Latest

function New-GitClone
{

    Param (
        [Parameter(Mandatory)]
        [string]$Repository,

        [string]$Branch = "master",

        [Parameter(Mandatory)]
        [string]$Destination
    )

    Write-Host "Cloning $Repository into $Destination"

    # GIT_REDIRECT_STDERR required for Windows due to Git sending default output to STDERR
    # See https://github.com/git/git/blob/b2f55717c7f9b335b7ac2e3358b0498116b94a5d/Documentation/git.txt#L712
    $env:GIT_REDIRECT_STDERR = "2>&1"
    $Output = git clone -b $Branch --single-branch --depth=1 $Repository `"$Destination`"

    if ($LastExitCode -ne 0)
    {
        Write-Error "Git error: " + $Output
    }

    Get-Item $Destination
}

function ConvertTo-Hashtable
{
    Param (
        [Parameter(Mandatory, ValueFromPipeLine)]
        [pscustomobject]$Value
    )

    Process {
        $Output = @{ }
        $Value | Get-Member -MemberType NoteProperty |
                Select  -ExpandProperty Name |
                % { $Output.$_ = $Value.$_ } |
                Out-Null
        $Output
    }
}

function Limit-HashtableKey
{
    Param (
        [Parameter(Mandatory, ValueFromPipeLine)]
        [hashtable]$Hash,

        [Parameter(Mandatory)]
        [string[]]$Keys
    )

    $Output = @{ }
    foreach ($Key in $Hash.Keys)
    {
        if ($Keys -contains $Key)
        {
            $Output.$Key = $Hash.$Key
        }
    }
    $Output
}

function Merge-Hashtable
{
    $Output = @{ }
    foreach ($Hash in ($Input + $Args))
    {
        if ($Hash -is [hashtable])
        {
            foreach ($Key in $Hash.Keys)
            {
                $Output.$Key = $Hash.$Key
            }
        }
    }
    $Output
}

function Get-RandomString
{
    Param (
        [Alias("Count")]
        [int]$Length = 8
    )
    -join ((65..90) + (97..122) | Get-Random -Count $Length | % { [char]$_ })
}

function Remove-HashtableKey
{
    Param (
        [Parameter(Mandatory, ValueFromPipeLine, Position=0)]
        $Hash,

        [Parameter(Mandatory, ParameterSetName = "single")]
        [string]$Key,

        [Parameter(Mandatory, ParameterSetName = "array")]
        [string[]]$Keys
    )

    Process {

        [hashtable]$Output = $Hash.Clone()

        if ($Key)
        {
            $Keys = @($Key)
        }

        foreach ($K in $Keys)
        {
            $Output.Remove($K)
        }

        $Output
    }
}

function Compare-Hashtable
{
    [OutputType([bool])]
    Param (
        [Parameter(Mandatory, Position=0)]
        [hashtable]$Hash,

        [Parameter(Mandatory, Position=1)]
        [hashtable]$Hash2
    )

    Process {

        if ($Null -ne (Compare-Object $Hash.Keys $Hash2.Keys)) {
            return $False;
        }

        foreach ($Key in $Hash.Keys)
        {
            $Ref = $Hash.$Key
            $Diff = $Hash2.$Key

            if ($Ref.GetType().FullName -ne $Diff.GetType().FullName)
            {
                return $False
            }
            if ($Ref -is [hashtable]) {
                if (!(Compare-Hashtable $Ref $Diff)) {
                    return $False;
                }
                continue
            }
            if ($Ref -is [array]) {
                if ($Null -ne (Compare-Object $Ref $Diff)) {
                    return $False;
                }
                continue
            }
            if ($Ref -is [pscustomobject]) {
                if ($Null -ne (Compare-Object $Ref.PsObject.Properties $Diff.PsObject.Properties)) {
                    return $False;
                }
                continue
            }
            if ($Ref -ne $Diff) {
                return $False
            }
        }

        $True
    }
}
