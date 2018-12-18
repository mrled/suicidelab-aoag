Configuration AoagLab {
    param (
        [Parameter(Mandatory)] [string[]] $SqlServerIniContents,
        [Parameter(Mandatory)] [SecureString] $SqlServerSaPassword,
        [PSCredential] $Credential = (Get-Credential -Credential 'Administrator')
    )
    Import-DscResource -Module PSDesiredStateConfiguration

    Import-DscResource -Module xActiveDirectory -ModuleVersion 2.17.0.0
    Import-DscResource -Module xComputerManagement -ModuleVersion 4.1.0.0
    Import-DscResource -Module xDHCPServer -ModuleVersion 1.6.0.0
    Import-DscResource -Module xDnsServer -ModuleVersion 1.7.0.0
    Import-DscResource -Module xFailOverCluster -ModuleVersion 1.10.0.0
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

        xADUser SqlServiceAccountName {
            DomainName  = $node.DomainName;
            UserName    = $node.SqlServiceAccountName;
            Description = 'SQL Server Service Account';
            Password    = $node.SqlServiceAccountPassword
            Ensure      = 'Present';
            DependsOn   = '[xADDomain]ADDomain';
        }

    }

    node $AllNodes.Where({$_.Role -in 'DC'}).NodeName {
        xWaitForCluster 'DcWaitForCluster' {
            Name                = $node.ClusterName
            RetryIntervalSec    = 10
            RetryCount          = 60
            DependsOn           = "[xADDomain]ADDomain"
        }

        File "CreateClusterWitnessDirectory" {
            Type = 'Directory'
            DestinationPath = 'C:\TestClusterWitness'
            Ensure = "Present"
            DependsOn   = '[xWaitForCluster]DcWaitForCluster';
        }

        xSmbShare "CreateClusterWitnessShare" {
            Ensure = "Present"
            Name = $node.ClusterWitnessShare
            Path = "C:\TestClusterWitness"
            Description = "A fileshare witness for the test cluster"
            FullAccess = @(
                "Administrator@$($node.DomainName)"
                "User1@$($node.DomainName)"
                # Setting permissions for the **cluster computer account**
                # There will be a computer account created with the cluster name when the cluster is created
                # See also <https://docs.microsoft.com/en-us/windows-server/failover-clustering/manage-cluster-quorum>
                "$($node.ClusterName)@$($node.DomainName)"
            )
            DependsOn   = '[File]CreateClusterWitnessDirectory';
        }

        File "CreateClusterBackupDirectory" {
            Type = 'Directory'
            DestinationPath = 'C:\TestClusterBackup'
            Ensure = "Present"
            DependsOn   = '[xWaitForCluster]DcWaitForCluster';
        }

        xSmbShare "CreateClusterBackupShare" {
            Ensure = "Present"
            Name = $node.ClusterBackupShare
            Path = "C:\TestClusterBackup"
            Description = "A fileshare for SQL backups for the test cluster"
            FullAccess = @(
                "Administrator@$($node.DomainName)"
                "User1@$($node.DomainName)"
                "$($node.SqlServiceAccountName)@$($node.DomainName)"
            )
            DependsOn   = '[File]CreateClusterBackupDirectory';
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
            'RSAT-Clustering'
        )) {
            WindowsFeature "SqlServer_$($feature.Replace('-',''))" {
                Ensure               = 'Present';
                Name                 = $feature;
                IncludeAllSubFeature = $true;
                DependsOn            = '[xComputer]DomainMembership';
            }
        }

        File SqlServerConfigurationFile {
            Contents = $SqlServerIniContents -Join "`r`n"
            DestinationPath = "C:\SqlServerConfigurationFile.ini"
            Type = "File"
            Ensure = "Present"
            DependsOn = "[xComputer]DomainMembership"
        }

        Script InstallSQLServer {
            GetScript = {
                $sqlInstances = Get-WmiObject -Class win32_service -ComputerName localhost |
                    Where-Object -Property Name -Match "mssql*" -and -Property PathName -Match "sqlservr.exe" |
                    Select-Object -ExpandProperty Caption
                $res = $sqlInstances -ne $null -and $sqlInstances -gt 0
                return @{
                    Installed = $res;
                    InstanceCount = $sqlInstances.count
                }
            }
            TestScript = {
                $sqlInstances = Get-WmiObject -Class win32_service -ComputerName localhost |
                    Where-Object -Property Name -Match "mssql*" -and -Property PathName -Match "sqlservr.exe" |
                    Select-Object -ExpandProperty Caption
                return $sqlInstances -ne $null -and $sqlInstances -gt 0
            }
            SetScript = {
                $securePass = ${using:SqlServerSaPassword}
                $plainPass = (New-Object -TypeName PSCredential -ArgumentList @('ignored', $securePass)).GetNetworkCredential().Password
                # NOTE: Logs saved in $env:ProgramFiles\Microsoft SQL Server\120\Setup Bootstrap\Log
                Start-Process -NoNewWindow -Wait -FilePath "C:\Resources\SqlServer2016Eval\Setup.exe" -ArgumentList @(
                    "/ConfigurationFile=C:\SqlServerConfigurationFile.ini"
                    "/SQLSVCPASSWORD=$plainPass"
                    "/AGTSVCPASSWORD=$plainPass"
                    "/SAPWD=$plainPass"
                )
            }
            DependsOn = "[File]SqlServerConfigurationFile"
        }

        Script InstallSSMS {
            GetScript = { return @{ Result = "" } }
            TestScript = {
                Test-Path -Path "C:\Program Files (x86)\Microsoft SQL Server\140\Tools\Binn\ManagementStudio\Ssms.exe"
            }
            SetScript = {
                Start-Process -NoNewWindow -Wait -FilePath "C:\Resources\SSMS-Setup-ENU.exe" -ArgumentList @(
                    '/install'
                    '/quiet'
                    '/norestart'
                )
            }
            DependsOn = "[Script]InstallSQLServer"
        }

        # Default SQL Server port
        # NOT used for connecting to the normal SQL instance;
        # used instead to connect to the AOAG listener.
        xFirewall 'EnableSqlDefaultPort' {
            Name        = 'SQLSERVER';
            DisplayName = 'SQL Server';
            Direction   = 'Inbound';
            Action      = 'Allow';
            Ensure      = 'Present';
            Enabled     = 'True';
            Profile     = 'Any';
            LocalPort   = 1433;
        }

        # Nonstandard port we use for SQL Server
        # This will connect directly to the SQL Server,
        # without going through an AOAG listener
        xFirewall 'EnableSqlCustomPort' {
            Name        = 'SQLSERVER-CustomPort';
            DisplayName = 'SQL Server custom listen port';
            Direction   = 'Inbound';
            Action      = 'Allow';
            Ensure      = 'Present';
            Enabled     = 'True';
            Profile     = 'Any';
            LocalPort   = 11433;
        }

        # This is required for some reason
        xFirewall 'EnableHadrEndpointPort' {
            Name        = 'HADREndpoint';
            DisplayName = 'HADR Endpoint port';
            Direction   = 'Inbound';
            Action      = 'Allow';
            Ensure      = 'Present';
            Enabled     = 'True';
            Profile     = 'Any';
            LocalPort   = 5022;
        }

    }

    # Create the cluster on the first node...
    node 'AOAGLAB-SQL1' {

        $dcName = $AllNodes.Where({$_.Role -in 'DC'}).NodeName | Select-Object -First 1

        # Get-Cluster -Name whatever
        # New-Cluster -Name whatever -StaticAddress 192.168.1.66/24 -Node @('lab-sql1', 'lab-sql2') -Force
        xCluster 'CreateAoagCluster' {
            Name = $node.ClusterName
            StaticIPAddress = $node.ClusterAddress
            DomainAdministratorCredential = $Credential
            DependsOn = "[WindowsFeature]RSATClustering"
        }

        # Get-ClusterQuorum
        # Set-ClusterQuorum -Cluster whatever -NodeAndFileShareMajority \\example.com\witnessshare
        xClusterQuorum 'SetQuorumToNodeAndDiskMajority' {
            IsSingleInstance = 'Yes'
            Type             = 'NodeAndFileShareMajority'
            Resource         = "\\$dcName\$($node.ClusterWitnessShare)"
            DependsOn = "[xCluster]CreateAoagCluster"
        }
    }

    # Join the cluster for all other nodes...
    node $AllNodes.Where({$_.Role -in 'SQL' -and $_.NodeName -ne 'AOAGLAB-SQL1'}).NodeName {
        xWaitForCluster 'WaitForCluster' {
            Name                = $node.ClusterName
            RetryIntervalSec    = 10
            RetryCount          = 60
            DependsOn           = "[WindowsFeature]RSATClustering"
        }
        xCluster 'JoinCluster' {
            Name                          = 'Cluster01'
            StaticIPAddress               = '192.168.100.20/24'
            DomainAdministratorCredential = $Credential
            DependsOn                     = '[xWaitForCluster]WaitForCluster'
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