$ErrorActionPreference = "Stop"

$labConfigurationName = "AoagLab"

Configuration "$labConfigurationName" {
    param (
        [Parameter()] [ValidateNotNull()] [PSCredential] $Credential = (Get-Credential -Credential 'Administrator')
    )
    Import-DscResource -Module PSDesiredStateConfiguration

    Import-DscResource -Module xActiveDirectory -ModuleVersion 2.17.0.0
    Import-DscResource -Module xComputerManagement -ModuleVersion 4.1.0.0
    Import-DscResource -Module xDHCPServer -ModuleVersion 1.6.0.0
    Import-DscResource -Module xDnsServer -ModuleVersion 1.7.0.0
    Import-DscResource -Module xNetworking -ModuleVersion 5.5.0.0
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

            if (-not [System.String]::IsNullOrEmpty($node.DefaultGateway)) {
                xDefaultGatewayAddress 'PrimaryDefaultGateway' {
                    InterfaceAlias = $node.InterfaceAlias;
                    Address        = $node.DefaultGateway;
                    AddressFamily  = $node.AddressFamily;
                }
            }

            if (-not [System.String]::IsNullOrEmpty($node.DnsServerAddress)) {
                xDnsServerAddress 'PrimaryDNSClient' {
                    Address        = $node.DnsServerAddress;
                    InterfaceAlias = $node.InterfaceAlias;
                    AddressFamily  = $node.AddressFamily;
                }
            }

            if (-not [System.String]::IsNullOrEmpty($node.DnsConnectionSuffix)) {
                xDnsConnectionSuffix 'PrimaryConnectionSuffix' {
                    InterfaceAlias           = $node.InterfaceAlias;
                    ConnectionSpecificSuffix = $node.DnsConnectionSuffix;
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

    node $AllNodes.Where({$_.Role -in 'DC'}).NodeName {

        xComputer 'Hostname' {
            Name = $node.NodeName;
        }

        ## Hack to fix DependsOn with hypens "bug" :(
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

        # WindowsFeature AddRoutingComponent {
        #     Ensure               = 'Present';
        #     Name                 = 'Routing';
        #     IncludeAllSubFeature = $true;
        #     DependsOn            = '[xComputer]DomainMembership';
        # }

        # Script ConfigureRRAS {
        #     GetScript = { return @{ Result = "" } }
        #     TestScript = { return $false }
        #     SetScript = {
        #         Install-RemoteAccess -VpnType VPN
        #         cmd.exe /c "netsh routing ip nat install"
        #         cmd.exe /c "netsh routing ip nat add interface AOAGLAB-INTERNET"
        #         cmd.exe /c "netsh routing ip nat set interface AOAGLAB-INTERNET mode=full"
        #         cmd.exe /c "netsh routing ip nat add interface AOAGLAB-CORPNET-ETHERNET"
        #     }
        #     PsDscRunAsCredential = $Credential
        #     DependsOn            = '[WindowsFeature]AddRoutingComponent';
        # }

        # xIPAddress 'SecondaryIPAddress' {
        #     IPAddress      = $node.SecondaryIPAddress
        #     InterfaceAlias = $node.SecondaryInterfaceAlias
        #     AddressFamily  = $node.AddressFamily
        #     # DependsOn            = '[Script]ConfigureRRAS';
        #     DependsOn      = '[xComputer]DomainMembership';
        # }

        # xDnsServerAddress 'SecondaryDNSClient' {
        #     Address        = $node.SecondaryDnsServerAddress;
        #     InterfaceAlias = $node.SecondaryInterfaceAlias;
        #     AddressFamily  = $node.AddressFamily
        #     # DependsOn            = '[Script]ConfigureRRAS';
        #     DependsOn      = '[xComputer]DomainMembership';
        # }

        # xDnsConnectionSuffix 'SecondarySuffix' {
        #     InterfaceAlias           = $node.SecondaryInterfaceAlias;
        #     ConnectionSpecificSuffix = $node.SecondaryDnsConnectionSuffix;
        #     # DependsOn            = '[Script]ConfigureRRAS';
        #     DependsOn                = '[xComputer]DomainMembership';
        # }

        # xDhcpClient 'DhcpClient' {
        #     InterfaceAlias = $node.SecondaryInterfaceAlias
        #     AddressFamily  = $node.AddressFamily
        #     State           = "Enabled"
        #     # DependsOn       = '[Script]ConfigureRRAS';
        #     DependsOn       = '[xComputer]DomainMembership';
        # }

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

$configData = "$PSScriptRoot\AOAGLAB.ConfigData.psd1"
$adminCred = New-Object -TypeName PSCredential -ArgumentList @(
    "Administrator",
    ('mean solely signify dewberry 3.X' | ConvertTo-SecureString -AsPlainText -Force)
)
$configRoot = Get-LabHostDefault | Select-Object -ExpandProperty ConfigurationPath
& $labConfigurationName -ConfigurationData $configData -OutputPath $configRoot -Credential $adminCred -Verbose
Test-LabConfiguration -ConfigurationData $configData -Verbose
Start-LabConfiguration -ConfigurationData $configData -Verbose -Credential $adminCred
Start-Lab -ConfigurationData $configData -Verbose
