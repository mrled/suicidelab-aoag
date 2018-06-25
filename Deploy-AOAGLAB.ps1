[CmdletBinding()] Param(
    [string] $ConfigurationData = (Join-Path -Path $PSScriptRoot -ChildPath ConfigurationData.AOAGLAB.psd1),
    [string] $ConfigureScript = (Join-Path -Path $PSScriptRoot -ChildPath Configure.AOAGLAB.ps1),
    [string] $SqlServerConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath SqlServerConfigurationFile.ini),
    [string] $DscConfigName = "AoagLab",
    [SecureString] $AdminPassword = ('mean solely signify dewberry 3.X' | ConvertTo-SecureString -AsPlainText -Force),
    [SecureString] $SqlServerSaPassword = ('coral.obligate.vintage.clip.34' | ConvertTo-SecureString -AsPlainText -Force),
    [switch] $DeleteExisting,
    [switch] $IgnorePendingReboot
)

$ErrorActionPreference = "Stop"

$Error.Clear()

if (Get-Module -Name Lability) {
    Write-Verbose -Message "Removing Lability module..."
    Remove-Module -Name Lability -Verbose:$false
} else {
    Write-Verbose -Message "Lability module not imported."
}
Write-Verbose -Message "Importing Lability module..."
Import-Module -Name Lability -Verbose:$false

if ($DeleteExisting) {
    Write-Host -Object "Deleting existing resources"
    try {
        Get-VM -Name "AOAGLAB-*" -Verbose -ErrorAction Stop |
            Stop-VM -TurnOff -PassThru -Force -Verbose -ErrorAction Stop |
            Remove-VM -Force -Verbose -ErrorAction Stop
        Write-Verbose -Message "Deleted lab VMs"
    } catch {
        Write-Verbose -Message "No lab VMs found"
    }
    $vmDiskFilePattern = "${env:LabilityDifferencingVhdPath}\AOAGLAB*"
    while (Test-Path -Path $vmDiskFilePattern) {
        try {
            Remove-Item -Path $vmDiskFilePattern -Force -Verbose -ErrorAction Stop
        } catch {
            Start-Sleep -Seconds 2
        }
    }
}

$adminCred = New-Object -TypeName PSCredential -ArgumentList @("Administrator", $AdminPassword)
$sqlServerConfig = Get-Content -Path $SqlServerConfigPath

. $ConfigureScript
& $DscConfigName -ConfigurationData $ConfigurationData -OutputPath $env:LabilityConfigurationPath -Verbose -Credential $adminCred -SqlServerIniContents $sqlServerConfig
Start-LabConfiguration -ConfigurationData $ConfigurationData -Path $env:LabilityConfigurationPath -Verbose -Password $AdminPassword -IgnorePendingReboot:$IgnorePendingReboot
Start-Lab -ConfigurationData $ConfigurationData -Verbose
