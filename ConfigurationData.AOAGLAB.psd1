@{
    AllNodes = @(
        @{
            NodeName                    = '*';
            InterfaceAlias              = 'Ethernet';
            AddressFamily               = 'IPv4';
            DnsConnectionSuffix         = 'aoaglab.vlack.com';
            DnsServerAddress            = '10.0.0.1';
            DefaultGateway              = '10.0.0.2';
            DomainName                  = 'aoaglab.vlack.com';
            PSDscAllowPlainTextPassword = $true;
            PSDscAllowDomainUser        = $true; # Removes 'It is not recommended to use domain credential for node X' messages

            Lability_SwitchName         = 'AOAGLAB-CORPNET';
            Lability_StartupMemory      = 3GB;
            Lability_Media              = "2016_x64_Standard_EN_Eval";
            Lability_Timezone           = "Central Standard Time";

            ClusterName                 = "AOAGCLUSTER"
            ClusterIp                   = "10.0.0.90/24"
            ClusterWitnessShare         = "TestClusterWitness"
            ClusterBackupShare          = "TestClusterBackup"
            SqlServiceAccountName       = "SqlService"
            SqlServiceAccountPassword   = '|dsAdOv$anX$ZSsA'
        }
        @{
            NodeName                = 'AOAGLAB-DC1';
            IPAddress               = '10.0.0.1/24';
            DnsServerAddress        = '127.0.0.1';
            Role                    = 'DC';
            Lability_ProcessorCount = 1;
            Lability_Resource       = @(
                'Firefox'
            )
        }
        @{
            NodeName                     = 'AOAGLAB-EDGE1';
            Role                         = 'EDGE'
            Lability_ProcessorCount      = 1

            IPAddress                    = '10.0.0.2/24';

            # This VM acts as a NAT gateway between AOAGLAB-CORPNET and whatever network my WiFi adapter is connected to
            # (Which almost certainly means that AOAGLAB-CORPNET is double-NAT'ed).
            # However, the order that the switches get connected is not deterministic.
            # Therefore, we have to set MAC addresses for each interface,
            # rename each interface based on the MAC address,
            # and then configure IP addresses etc based on the new name of the interface.
            # Technique found here:
            # - https://github.com/VirtualEngine/Lability/blob/dev/Examples/MultipleNetworkExample.ps1
            # - https://github.com/VirtualEngine/Lability/blob/dev/Examples/MultipleNetworkExample.psd1
            # and mentioned here as a solution for our problem:
            # - https://github.com/VirtualEngine/Lability/issues/176
            #
            # Hyper-V MAC address range '00-15-5d-00-00-00' thru '00-15-5d-ff-ff-ff'.
            # WARNING: BE CAREFUL OF DUPLICATE MAC ADDRESSES IF USING EXTERNAL SWITCHES!
            Lability_MACAddress         = @('00-15-5d-cf-01-01', '00-15-5d-cf-01-02')
            Lability_SwitchName         = @('Default Switch', 'AOAGLAB-CORPNET')
            InterfaceAlias              = @('Public Network', 'Domain Network')

            Lability_Resource           = @(
                'Firefox'
            )
        }
        # @{
        #     NodeName                  = 'AOAGLAB-WEB1';
        #     IPAddress                 = '10.0.0.3/24';
        #     Role                      = 'WEB';
        #     Lability_ProcessorCount   = 1;
        # }
        @{
            NodeName                  = 'AOAGLAB-SQL1';
            IPAddress                 = '10.0.0.10/24';
            Role                      = 'SQL';
            Lability_ProcessorCount   = 1;
            Lability_Resource         = @(
                'Firefox'
                'SqlServer2016Eval'
                'SSMS2017'
            )
        }
        @{
            NodeName                  = 'AOAGLAB-SQL2';
            IPAddress                 = '10.0.0.11/24';
            Role                      = 'SQL';
            Lability_ProcessorCount   = 1;
            Lability_Resource         = @(
                'Firefox'
                'SqlServer2016Eval'
                'SSMS2017'
            )
        }
    )
    NonNodeData = @{
        Lability = @{
            Media = @()
            Network = @(
                # Use a *private* switch, not an internal one,
                # so that our Hyper-V host doesn't get a NIC w/ DHCP lease on the corporate network,
                # which can cause networking problems on the host.
                @{ Name = 'AOAGLAB-CORPNET'; Type = 'Private'; }

                # THe 'Default Switch' is installed with Hyper-V and is not managed here
            )

            DSCResource = @(
                @{ Name = 'xActiveDirectory'; RequiredVersion = '2.17.0.0'; }
                @{ Name = 'xComputerManagement'; RequiredVersion = '4.1.0.0'; }
                @{ Name = 'xDhcpServer'; RequiredVersion = '1.6.0.0'; }
                @{ Name = 'xDnsServer'; RequiredVersion = '1.7.0.0'; }
                @{ Name = 'xFailOverCluster'; RequiredVersion = '1.10.0.0'; }
                @{ Name = 'xNetworking'; RequiredVersion = '5.7.0.0'; }
                @{ Name = 'xSmbShare'; RequiredVersion = '2.0.0.0'; }
            )

            Resource = @(
                @{
                    Id = 'Firefox'
                    Filename = 'Firefox-Latest.exe'
                    Uri = 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US'
                }
                @{
                    Id = 'SqlServer2016Eval'
                    Filename = 'SQLServer2016SP2-FullSlipstream-x64-ENU.iso'
                    Uri = 'https://download.microsoft.com/download/4/1/A/41AD6EDE-9794-44E3-B3D5-A1AF62CD7A6F/sql16_sp2_dlc/en-us/SQLServer2016SP2-FullSlipstream-x64-ENU.iso'
                    Expand = $true
                    Checksum = "87fc4cb4d62a9278c6e2a76e28b9cd79"
                }
                @{
                    Id = 'SSMS2017'
                    Filename = "SSMS-Setup-ENU.exe"
                    Uri = "https://download.microsoft.com/download/0/D/2/0D26856F-E602-4FB6-8F12-43D2559BDFE4/SSMS-Setup-ENU.exe"
                    Checksum = 'BA07866DEB8CA9E8A42A0E6BA1328082'
                }
            )
        }
    }
}
