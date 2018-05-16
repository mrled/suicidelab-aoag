#Requires -Version 5
#Requires -RunAsAdministrator

<#
.SYNOPSIS
Apply DSC configurations
#>
[CmdletBinding()] Param(
    $ConfigurationName = "*"
)

# Comments for the Requires settings at the top of this file
# (Comments cannot precede "Requires" statements, so this is down here)
# - Requires -Version 5:            We use Powershell 5.x concepts
# - Requires -RunAsAdministrator:   This script sets machine settings and must be run as an admin
# - Requires -PSEdition Desktop:    Not present, but true
#                                   This is only 5.1 while we want to work on newly imaged 5.0 machines too

$ErrorActionPreference = "Stop"


## Globals I'll use later

$script:RepoModulesPath = Resolve-Path -LiteralPath $PSScriptRoot\Modules | Select-Object -ExpandProperty Path
$script:RequiredDscModules = @(
    # 'xComputerManagement'
    'xHyper-V'
)
$script:Configurations = @(
    "InstallHyperV"
    "DownloadEvalSoftware"
)

## Helper Functions

<#
.SYNOPSIS
Create a temporary directory
#>
function New-TemporaryDirectory {
    [CmdletBinding()] Param()
    do {
        $newTempDirPath = Join-Path $env:TEMP (New-Guid | Select-Object -ExpandProperty Guid)
    } while (Test-Path -Path $newTempDirPath)
    New-Item -ItemType Directory -Path $newTempDirPath
}

<#
.SYNOPSIS
Invoke a Powershell DSC configuration
.DESCRIPTION
Invoke a Powershell DSC configuration by compiling it to a temporary directory,
running it immediately from that location,
and then removing the temporary directory.
.PARAMETER Name
The name of the DSC configuration to invoke
.PARAMETER Parameters
Parameters to pass to the DSC configuration
#>
function Invoke-DscConfiguration {
    [CmdletBinding()] Param(
        [Parameter(Mandatory)] [string] $Name,
        [hashtable] $Parameters = @{}
    )

    $dscWorkDir = New-TemporaryDirectory
    $Parameters.OutputPath = $dscWorkDir.FullName
    Write-Verbose -Message "Using working directory at $($dscWorkDir.FullName)"

    try {
        & "$Name" @Parameters
        Start-DscConfiguration -Path $dscWorkDir -Wait -Force
    } finally {
        Remove-Item -Recurse -Force -Path $dscWorkDir
    }
}

<#
.SYNOPSIS
Remove a value from a PATH-like environment variable
.PARAMETER Name
The name of the environment variable
.PARAMETER Value
The value to remove from the environment variable
.PARAMETER TargetLocation
The environment location
#>
function Remove-PathLikeEnvironmentVariableValue {
    [CmdletBinding()] Param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Value,
        [Parameter(Mandatory)] [ValidateSet('Process', 'User', 'Machine')] [string[]] $TargetLocation
    )
    foreach ($location in $TargetLocation) {
        $currentValue = [Environment]::GetEnvironmentVariable($Name, $location)
        $currentValueSplit = $currentValue -Split ';'
        if ($currentValueSplit -Contains $Value) {
            Write-Verbose -Message "Removing value '$Value' from '$location' '$Name' environment variable"
            $newValue = ($currentValueSplit | Foreach-Object -Process { if ($_ -ne $Value) {$_} }) -Join ";"
            [Environment]::SetEnvironmentVariable($Name, $newValue, $location)
        } else {
            Write-Verbose -Message "The value '$Value' is not a member of '$location' '$Name' environment variable"
        }
    }
}

<#
.SYNOPSIS
Append a value to a PATH-like environment variable
.PARAMETER Name
The name of the environment variable
.PARAMETER Value
The value to add to the environment variable
.PARAMETER  Location
The environment location
#>
function Add-PathLikeEnvironmentVariableValue {
    [CmdletBinding()] Param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Value,
        [Parameter(Mandatory)] [ValidateSet('Process', 'User', 'Machine')] [string[]] $TargetLocation
    )
    foreach ($location in $TargetLocation) {
        $currentValue = [Environment]::GetEnvironmentVariable($Name, $location)
        $currentValueSplit = $currentValue -Split ';'
        if ($currentValueSplit -NotContains $Value) {
            Write-Verbose -Message "Adding value '$Value' to '$location' '$Name' environment variable"
            [Environment]::SetEnvironmentVariable($Name, "$currentValue;$Value", $location)
        } else {
            Write-Verbose -Message "The value '$Value' is already a member of the '$location' '$Name' environment variable"
        }
    }
}

# Allow dot-sourcing the script without running
# (Useful during debugging)
# If dot-sourced, the following block will not run:
if ($MyInvocation.InvocationName -ne '.') {
    foreach ($mod in $script:RequiredDscModules) {
        if (-not (Get-Module -Name $mod -ListAvailable)) {
            Write-Verbose -Message "Installing Powershell module $mod"
            Install-Module -Name $mod
        } else {
            Write-Verbose -Message "Powershell module $mod is already installed"
        }
    }

    try {
        # Set the machine's PSModulePath so that when we DSC gains admin privs, it can find the modules
        # Set the process's PSModulePath because I'm cargo culting for speed
        Add-PathLikeEnvironmentVariableValue -Name PSModulePath -Value $script:RepoModulesPath -TargetLocation $("Machine", "Process")

        Get-ChildItem -Path $PSScriptRoot\Configurations\* -Include *.ps1 |
            Foreach-Object -Process { . $_ }

        foreach ($config in $script:Configurations) {
            if ($ConfigurationName -like $config) {
                Invoke-DscConfiguration -Name $config -Verbose:$Verbose
            }
        }

    } finally {
        # We don't want our module path to stick around in the machine's module path
        Remove-PathLikeEnvironmentVariableValue -Name PSModulePath -Value $script:RepoModulesPath -TargetLocation "Machine"
    }
}
