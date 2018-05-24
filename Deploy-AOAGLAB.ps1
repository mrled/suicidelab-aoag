[CmdletBinding()] Param(
    [string] $LabConfigurationName = "AoagLab",
    [string] $AdminPassword = 'mean solely signify dewberry 3.X',
    [switch] $DeleteExistingDisks
)

$ErrorActionPreference = "Stop"

Configuration "$LabConfigurationName" {
    param (
        [Parameter()] [ValidateNotNull()] [PSCredential] $Credential = (Get-Credential -Credential 'Administrator')
    )
    Import-DscResource -Module PSDesiredStateConfiguration

    Import-DscResource -Module xActiveDirectory -ModuleVersion 2.17.0.0
    Import-DscResource -Module xComputerManagement -ModuleVersion 4.1.0.0
    Import-DscResource -Module xDHCPServer -ModuleVersion 1.6.0.0
    Import-DscResource -Module xDnsServer -ModuleVersion 1.7.0.0
    Import-DscResource -Module xNetworking -ModuleVersion 5.7.0.0
    Import-DscResource -Module xSmbShare -ModuleVersion 2.0.0.0

    node $AllNodes.Where({$true}).NodeName {

        LocalConfigurationManager {
            RebootNodeIfNeeded   = $true;
            AllowModuleOverwrite = $true;
            ConfigurationMode    = 'ApplyOnly';
            CertificateID        = $node.Thumbprint;
        }

        if (-not [System.String]::IsNullOrEmpty($node.IPAddress)) {
            xIPAddress 'PrimaryIPAddress' {
                IPAddress      = $node.IPAddress
                InterfaceAlias = $node.InterfaceAlias
                AddressFamily  = $node.AddressFamily
            }

            if (-not [System.String]::IsNullOrEmpty($node.DnsServerAddress)) {
                xDnsServerAddress 'PrimaryDNSClient' {
                    Address        = $node.DnsServerAddress;
                    InterfaceAlias = $node.InterfaceAlias;
                    AddressFamily  = $node.AddressFamily;
                    DependsOn      = '[xIPAddress]PrimaryIPAddress';
                }
            }

            if (-not [System.String]::IsNullOrEmpty($node.DnsConnectionSuffix)) {
                xDnsConnectionSuffix 'PrimaryConnectionSuffix' {
                    InterfaceAlias           = $node.InterfaceAlias;
                    ConnectionSpecificSuffix = $node.DnsConnectionSuffix;
                    DependsOn                = '[xIPAddress]PrimaryIPAddress';
                }
            }

        } #end if IPAddress

        xFirewall 'FPS-ICMP4-ERQ-In' {
            Name        = 'FPS-ICMP4-ERQ-In';
            DisplayName = 'File and Printer Sharing (Echo Request - ICMPv4-In)';
            Description = 'Echo request messages are sent as ping requests to other nodes.';
            Direction   = 'Inbound';
            Action      = 'Allow';
            Enabled     = 'True';
            Profile     = 'Any';
        }

        xFirewall 'FPS-ICMP6-ERQ-In' {
            Name        = 'FPS-ICMP6-ERQ-In';
            DisplayName = 'File and Printer Sharing (Echo Request - ICMPv6-In)';
            Description = 'Echo request messages are sent as ping requests to other nodes.';
            Direction   = 'Inbound';
            Action      = 'Allow';
            Enabled     = 'True';
            Profile     = 'Any';
        }
    } #end nodes ALL

    # Do not set the default gateway for the EDGE server to avoid errors like
    # 'New-NetRoute : Instance MSFT_NetRoute already exists'
    # When this configuration was part of the .Where({$true}) stanza above,
    # I got those errors on EDGE all the time.
    node $AllNodes.Where({$_.Role -NotIn 'EDGE'}).NodeName {
        xDefaultGatewayAddress 'NonEdgePrimaryDefaultGateway' {
            InterfaceAlias = $node.InterfaceAlias;
            Address        = $node.DefaultGateway;
            AddressFamily  = $node.AddressFamily;
            DependsOn      = '[xIPAddress]PrimaryIPAddress';
        }
    }

    node $AllNodes.Where({$_.Role -in 'DC'}).NodeName {

        xComputer 'Hostname' {
            Name = $node.NodeName;
        }

        ## Hack to fix DependsOn with hyphens "bug" :(
        foreach ($feature in @(
                'AD-Domain-Services',
                'GPMC',
                'RSAT-AD-Tools',
                'DHCP',
                'RSAT-DHCP'
            )) {
            WindowsFeature $feature.Replace('-','') {
                Ensure               = 'Present';
                Name                 = $feature;
                IncludeAllSubFeature = $true;
            }
        }

        xADDomain 'ADDomain' {
            DomainName                    = $node.DomainName;
            SafemodeAdministratorPassword = $Credential;
            DomainAdministratorCredential = $Credential;
            DependsOn                     = '[WindowsFeature]ADDomainServices';
        }

        xDhcpServerAuthorization 'DhcpServerAuthorization' {
            Ensure    = 'Present';
            DependsOn = '[WindowsFeature]DHCP','[xADDomain]ADDomain';
        }

        xDhcpServerScope 'DhcpScope10_0_0_0' {
            Name          = 'Corpnet';
            IPStartRange  = '10.0.0.100';
            IPEndRange    = '10.0.0.200';
            SubnetMask    = '255.255.255.0';
            LeaseDuration = '00:08:00';
            State         = 'Active';
            AddressFamily = 'IPv4';
            DependsOn     = '[WindowsFeature]DHCP';
        }

        xDhcpServerOption 'DhcpScope10_0_0_0_Option' {
            ScopeID            = '10.0.0.0';
            DnsDomain          = 'corp.contoso.com';
            DnsServerIPAddress = '10.0.0.1';
            Router             = '10.0.0.2';
            AddressFamily      = 'IPv4';
            DependsOn          = '[xDhcpServerScope]DhcpScope10_0_0_0';
        }

        xADUser User1 {
            DomainName  = $node.DomainName;
            UserName    = 'User1';
            Description = 'Lability Test Lab user';
            Password    = $Credential;
            Ensure      = 'Present';
            DependsOn   = '[xADDomain]ADDomain';
        }

        xADGroup DomainAdmins {
            GroupName        = 'Domain Admins';
            MembersToInclude = 'User1';
            DependsOn        = '[xADUser]User1';
        }

        xADGroup EnterpriseAdmins {
            GroupName        = 'Enterprise Admins';
            GroupScope       = 'Universal';
            MembersToInclude = 'User1';
            DependsOn        = '[xADUser]User1';
        }

    } #end nodes DC

    node $AllNodes.Where({$_.Role -in 'WEB','SQL','EDGE'}).NodeName {
        # Use user@domain for the domain joining credential
        $upn = "$($Credential.UserName)@$($node.DomainName)"
        $domainCred = New-Object -TypeName PSCredential -ArgumentList ($upn, $Credential.Password);
        xComputer 'DomainMembership' {
            Name       = $node.NodeName;
            DomainName = $node.DomainName;
            Credential = $domainCred
        }
    } #end nodes DomainJoined

    node $AllNodes.Where({$_.Role -in 'EDGE'}).NodeName {

        Script "NewNetNat" {
            GetScript = { return @{ Result = "" } }
            TestScript = {
                try {
                    Get-NetNat -Name NATNetwork -ErrorAction Stop | Out-Null
                    return $true
                } catch {
                    return $false
                }
            }
            SetScript = {
                New-NetNat -Name NATNetwork -InternalIPInterfaceAddressPrefix "10.0.0.0/24"
            }
            PsDscRunAsCredential = $Credential
            DependsOn = '[xComputer]DomainMembership';
        }

    }

    node $Allnodes.Where({'Firefox' -in $_.Lability_Resource}).NodeName {
        Script "InstallFirefox" {
            GetScript = { return @{ Result = "" } }
            TestScript = {
                Test-Path -Path "C:\Program Files\Mozilla Firefox"
            }
            SetScript = {
                $ffInstaller = "C:\Resources\Firefox-Latest.exe"
                $firefoxIniFile = "${env:temp}\firefox-installer.ini"
                $firefoxIniContents = @(
                    "QuickLaunchShortcut=false"
                    "DesktopShortcut=false"
                )
                Out-File -FilePath $firefoxIniFile -InputObject $firefoxIniContents -Encoding UTF8
                $startProcParams = @{
                    FilePath = $ffInstaller
                    ArgumentList = @('/INI="{0}"' -f $firefoxIniFile)
                    Wait = $true
                    PassThru = $true
                }
                $process = Start-Process @startProcParams
                if ($process.ExitCode -ne 0) {
                    throw "Firefox installer at $ffInstaller exited with code $($process.ExitCode)"
                }
            }
            PsDscRunAsCredential = $Credential
        }
    }

    node $AllNodes.Where({$_.Role -in 'WEB'}).NodeName {
        foreach ($feature in @(
                'Web-Default-Doc',
                'Web-Dir-Browsing',
                'Web-Http-Errors',
                'Web-Static-Content',
                'Web-Http-Logging',
                'Web-Stat-Compression',
                'Web-Filtering',
                'Web-Mgmt-Tools',
                'Web-Mgmt-Console')) {
            WindowsFeature $feature.Replace('-','') {
                Ensure               = 'Present';
                Name                 = $feature;
                IncludeAllSubFeature = $true;
                DependsOn            = '[xComputer]DomainMembership';
            }
        }
    } #end nodes WEB

} #end Configuration Example

$Error.Clear()

if ($DeleteExistingDisks) {
    $vmDiskPath = Get-LabHostDefault | Select-Object -ExpandProperty DifferencingVhdPath
    do {
        Remove-Item -Path $vmDiskPath\AOAGLAB-* -ErrorAction SilentlyContinue -Force
        Start-Sleep -Seconds 2
    } while (Get-ChildItem -Path $vmDiskPath\AOAGLAB-*)
}

$configData = "$PSScriptRoot\AOAGLAB.ConfigData.psd1"
$adminCred = New-Object -TypeName PSCredential -ArgumentList @(
    "Administrator",
    ($AdminPassword | ConvertTo-SecureString -AsPlainText -Force)
)
$configRoot = Get-LabHostDefault | Select-Object -ExpandProperty ConfigurationPath
& $LabConfigurationName -ConfigurationData $configData -OutputPath $configRoot -Credential $adminCred -Verbose
Test-LabConfiguration -ConfigurationData $configData -Verbose
Start-LabConfiguration -ConfigurationData $configData -Verbose -Credential $adminCred -IgnorePendingReboot
Start-Lab -ConfigurationData $configData -Verbose
