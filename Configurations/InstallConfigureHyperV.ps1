<#
.DESCRIPTION
DSC configuration to install and configure Hyper-V. Requires administrative privileges.
#>

Configuration InstallHyperV {
    Param(
        [string[]] $ComputerName = "localhost"
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    Node $ComputerName {

        # NOTE: Client OSes cannot use WindowsFeature DSC resources, so we are resigned to this
        Script "EnableHyperV" {
            GetScript = { return @{ Result = "" } }
            TestScript = {
                $feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
                return $feature -eq [Microsoft.Dism.Commands.FeatureState]::Enabled
            }
            SetScript = {
                Enable-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V' -All
            }
        }

    }
}

# Make sure a path is absolute, even if it does not exist
function Get-AbsolutePath {
    [CmdletBinding()] Param(
        [Parameter(Mandatory)] [string] $Path
    )
    if ([System.IO.Path]::IsPathRooted($Path)) {
        # IsPathRooted() returns true for paths like \file.txt;
        # GetFullPath() will turn that into X:\file.txt
        return [System.IO.Path]::GetFullPath($Path)
    } else {
        return [System.IO.Path]::GetFullPath("$PWD\$Path")
    }
}

Configuration DownloadEvalSoftware {
    Param(
        [string[]] $ComputerName = "localhost"
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration

    $DownloadPath = Get-AbsolutePath -Path "$PSScriptRoot\..\bin"
    $Binaries = @{
        Server2016 = @{
            Uri = "https://download.microsoft.com/download/1/4/9/149D5452-9B29-4274-B6B3-5361DBDA30BC/14393.0.161119-1705.RS1_REFRESH_SERVER_EVAL_X64FRE_EN-US.ISO"
            Filename = "14393.0.161119-1705.RS1_REFRESH_SERVER_EVAL_X64FRE_EN-US.ISO"
        }
        Sql2016 = @{
            Uri = "https://download.microsoft.com/download/A/C/6/AC6F2802-4CC4-40B2-B333-395A4291EF29/SQLServer2016-SSEI-Eval.exe"
            Filename = "SQLServer2016-SSEI-Eval.exe"
        }
        Sql2017 = @{
            Uri = "https://download.microsoft.com/download/5/2/2/522EE642-941E-47A6-8431-57F0C2694EDF/SQLServer2017-SSEI-Eval.exe"
            Filename = "SQLServer2017-SSEI-Eval.exe"
        }
    }

    Node $ComputerName {

        File "EnsureDownloadPathExists" {
            Ensure = "Present"
            Type = "Directory"
            DestinationPath = $DownloadPath
        }
        Script "GetWindowsServer2016Iso" {
            GetScript = { return @{ Result = "" } }
            TestScript = {
                Write-Verbose -Message "Testing for existing file at $using:DownloadPath\$($using:Binaries.Server2016.Filename)"
                return Test-Path -Path "$using:DownloadPath\$($using:Binaries.Server2016.Filename)"
            }
            SetScript = {
                $uri = $using:Binaries.Server2016.Uri
                $dlPath = Join-Path -Path $using:DownloadPath -ChildPath $using:Binaries.Server2016.Filename
                Write-Verbose -Message "Downloading '$uri' to '$dlPath'"
                $client = New-Object -TypeName Net.WebClient
                $client.Downloadfile($uri, $dlPath)
            }
        }
        Script "GetSqlServer2016Exe" {
            GetScript = { return @{ Result = "" } }
            TestScript = {
                return Test-Path -Path "$using:DownloadPath\$($using:Binaries.Sql2016.Filename)"
            }
            SetScript = {
                $client = New-Object -TypeName Net.WebClient
                $client.Downloadfile($using:Binaries.Sql2016.Uri, "$using:DownloadPath\$($using:Binaries.Sql2016.Filename)")
            }
        }
    }
}
