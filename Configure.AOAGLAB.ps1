Configuration AoagLab {
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

    # Common configuration for all nodes
    node $AllNodes.Where({$true}).NodeName {

        LocalConfigurationManager {
            RebootNodeIfNeeded   = $true;
            AllowModuleOverwrite = $true;
            ConfigurationMode    = 'ApplyOnly';
            CertificateID        = $node.Thumbprint;
        }

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

    }

    node $AllNodes.Where({$_.Role -in 'EDGE'}).NodeName {

        xNetAdapterName "RenamePublicAdapter" {
            NewName     = $node.InterfaceAlias[0];
            MacAddress  = $node.Lability_MACAddress[0];
        }
        # Do not specify an IP address for the public adapter so that it gets one via DHCP

        xNetAdapterName "RenameCorpnetAdapter" {
            NewName     = $node.InterfaceAlias[1];
            MacAddress  = $node.Lability_MACAddress[1];
        }

        xIPAddress 'CorpnetIPAddress' {
            IPAddress      = $node.IPAddress;
            InterfaceAlias = $node.InterfaceAlias[1];
            AddressFamily  = $node.AddressFamily;
            DependsOn      = '[xNetAdapterName]RenameCorpnetAdapter';
        }

        xDnsServerAddress 'CorpnetDNSClient' {
            Address        = $node.DnsServerAddress;
            InterfaceAlias = $node.InterfaceAlias[1];
            AddressFamily  = $node.AddressFamily;
            DependsOn      = '[xIPAddress]CorpnetIPAddress';
        }

        xDnsConnectionSuffix 'CorpnetConnectionSuffix' {
            InterfaceAlias           = $node.InterfaceAlias[1];
            ConnectionSpecificSuffix = $node.DnsConnectionSuffix;
            DependsOn                = '[xIPAddress]CorpnetIPAddress';
        }

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
            DependsOn = '[xIPAddress]CorpnetIPAddress';
        }
    }

    node $AllNodes.Where({$_.Role -NotIn 'EDGE'}).NodeName {

        xIPAddress 'CorpnetIPAddress' {
            IPAddress      = $node.IPAddress
            InterfaceAlias = $node.InterfaceAlias
            AddressFamily  = $node.AddressFamily
        }

        xDnsServerAddress 'PrimaryDNSClient' {
            Address        = $node.DnsServerAddress;
            InterfaceAlias = $node.InterfaceAlias;
            AddressFamily  = $node.AddressFamily;
            DependsOn      = '[xIPAddress]CorpnetIPAddress';
        }

        xDnsConnectionSuffix 'PrimaryConnectionSuffix' {
            InterfaceAlias           = $node.InterfaceAlias;
            ConnectionSpecificSuffix = $node.DnsConnectionSuffix;
            DependsOn                = '[xIPAddress]CorpnetIPAddress';
        }

        # Do not set the default gateway for the EDGE server to avoid errors like
        # 'New-NetRoute : Instance MSFT_NetRoute already exists'
        # When this configuration was part of the .Where({$true}) stanza above,
        # I got those errors on EDGE all the time.
        xDefaultGatewayAddress 'NonEdgePrimaryDefaultGateway' {
            InterfaceAlias = $node.InterfaceAlias;
            Address        = $node.DefaultGateway;
            AddressFamily  = $node.AddressFamily;
            DependsOn      = '[xIPAddress]CorpnetIPAddress';
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

    }

    node $AllNodes.Where({$_.Role -in 'DC'}).NodeName {
        File "CreateClusterWitnessDirectory" {
            Type = 'Directory'
            DestinationPath = 'C:\TestClusterWitness'
            Ensure = "Present"
            DependsOn   = '[xADDomain]ADDomain';
        }
        xSmbShare "CreateClusterWitnessShare" {
            Ensure = "Present"
            Name = "TestClusterWitness"
            Path = "C:\TestClusterWitness"
            Description = "A fileshare witness for the test cluster"
            DependsOn   = '[File]CreateClusterWitnessDirectory';
        }
    }

    node $AllNodes.Where({$_.Role -in 'WEB','SQL','EDGE'}).NodeName {
        # Use user@domain for the domain joining credential
        $upn = "$($Credential.UserName)@$($node.DomainName)"
        $domainCred = New-Object -TypeName PSCredential -ArgumentList ($upn, $Credential.Password);
        xComputer 'DomainMembership' {
            Name       = $node.NodeName;
            DomainName = $node.DomainName;
            Credential = $domainCred
            DependsOn  = '[xIPAddress]CorpnetIPAddress'
        }
    } #end nodes DomainJoined

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

    node $AllNodes.Where({$_.Role -in 'SQL'}).NodeName {

        foreach ($feature in @(
            'NET-Framework-Core'
            'NET-Framework-45-Core'
            'Failover-Clustering'
        )) {
            WindowsFeature "SqlServer_$($feature.Replace('-',''))" {
                Ensure               = 'Present';
                Name                 = $feature;
                IncludeAllSubFeature = $true;
                DependsOn            = '[xComputer]DomainMembership';
            }
        }

        # UNTESTED BELOW HERE

        # File SqlServerConfigurationFile {
        #     SourcePath = "SqlServerConfigurationFile.ini"
        #     DestinationPath = "C:\ConfigurationFile.ini"
        #     Type = "File"
        #     Ensure = "Present"
        #     DependsOn = "[xComputer]DomainMembership"
        # }

        # Script InstallSQLServer {
        #     GetScript = {
        #         $sqlInstances = Get-WmiObject -Class win32_service -ComputerName localhost |
        #             Where-Object -Property Name -Match "mssql*" -and -Property PathName -Match "sqlservr.exe" |
        #             Select-Object -ExpandProperty Caption
        #         $res = $sqlInstances -ne $null -and $sqlInstances -gt 0
        #         return @{
        #             Installed = $res;
        #             InstanceCount = $sqlInstances.count
        #         }
        #     }
        #     TestScript = {
        #         $sqlInstances = Get-WmiObject -Class win32_service -ComputerName localhost |
        #             Where-Object -Property Name -Match "mssql*" -and -Property PathName -Match "sqlservr.exe" |
        #             Select-Object -ExpandProperty Caption
        #         return $sqlInstances -ne $null -and $sqlInstances -gt 0
        #     }
        #     SetScript = {
        #         # NOTE: Logs saved in $env:ProgramFiles\Microsoft SQL Server\120\Setup Bootstrap\Log
        #         Start-Process -Path "C:\Resources\SqlServer2016Eval\Setup.exe" -ArgumentList @(
        #             "/ConfigurationFile=c:\temp\ConfigurationFile.ini"
        #             "/SQLSVCPASSWORD=P2ssw0rd"
        #             "/AGTSVCPASSWORD=P2ssw0rd"
        #             "/SAPWD=P2ssw0rd"
        #         )
        #     }
        #     DependsOn = "[File]SqlServerConfigurationFile"
        # }

        # Script InstallSSMS {
        #     GetScript = { return @{ Result = "" } }
        #     TestScript = {
        #         Test-Path -Path "C:\Program Files (x86)\Microsoft SQL Server\140\Tools\Binn\ManagementStudio\Ssms.exe"
        #     }
        #     SetScript = {
        #         Start-Process -Path "C:\Resources\SSMS-Setup-ENU.exe"
        #     }
        #     DependsOn = "[Script]InstallSQLServer"
        # }

        # xFirewall 'EnableSqlPort' {
        #     Name        = 'SQLSERVER';
        #     DisplayName = 'SQL Server';
        #     Direction   = 'Inbound';
        #     Action      = 'Allow';
        #     Ensure      = 'Present';
        #     Enabled     = 'True';
        #     Profile     = 'Any';
        #     LocalPort   = 1433;
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