@{
    AllNodes = @(
        @{
            NodeName                    = '*';
            InterfaceAlias              = 'Ethernet';
            DefaultGateway              = '10.0.0.2';
            AddressFamily               = 'IPv4';
            DnsServerAddress            = '10.0.0.1';
            DomainName                  = 'aoaglab.vlack.com';
            PSDscAllowPlainTextPassword = $true;
            PSDscAllowDomainUser        = $true; # Removes 'It is not recommended to use domain credential for node X' messages
            Lability_SwitchName         = 'AOAGLAB-CORPNET';
            Lability_ProcessorCount     = 1;
            Lability_StartupMemory      = 3GB;
            Lability_Media              = "2016_x64_Standard_EN_Eval";
            Lability_Timezone           = "Central Standard Time";

            Lability_HardDiskDrive   = @(
                @{
                    Generation = 'VHDX'
                    Type = 'Dynamic'
                    MaximumSizeBytes = 50GB;
                }
            )
        }
        @{
            NodeName                = 'AOAGLAB-DC1';
            IPAddress               = '10.0.0.1/24';
            DnsServerAddress        = '127.0.0.1';
            Role                    = 'DC';
            Lability_ProcessorCount = 2;
            Lability_BootOrder      = 1;
        }
        @{
            NodeName                     = 'AOAGLAB-EDGE1';
            IPAddress                    = '10.0.0.2/24';
            DnsConnectionSuffix          = 'aoaglab.vlack.com';
            # SecondaryIPAddress           = '131.107.0.2/24';
            SecondaryDnsServerAddress    = '1.1.1.1';
            SecondaryInterfaceAlias      = 'Ethernet 2';
            SecondaryDnsConnectionSuffix = 'isp.example.com';
            Role                         = 'EDGE';
            ## Windows sees the two NICs in reverse order, e.g. first switch is 'Ethernet 2' and second is 'Ethernet'!?
            Lability_SwitchName          = 'AOAGLAB-CORPNET','Wifi-HyperV-VSwitch';
            Lability_BootOrder           = 30;
        }
        @{
            NodeName            = 'AOAGLAB-WEB1';
            IPAddress           = '10.0.0.3/24';
            Role                = 'WEB';
            Lability_BootOrder  = 30;
        }
        @{
            NodeName            = 'AOAGLAB-SQL1';
            IPAddress           = '10.0.0.10/24';
            Role                = 'SQL';
            Lability_BootOrder  = 30;
        }
        @{
            NodeName            = 'AOAGLAB-SQL2';
            IPAddress           = '10.0.0.11/24';
            Role                = 'SQL';
            Lability_BootOrder  = 30;
        }
    )
    NonNodeData = @{
        Lability = @{
            Media = @()
            Network = @(
                @{ Name = 'AOAGLAB-CORPNET'; Type = 'Internal'; }
                # The Wifi-HyperV-VSwitch is already defined on my machine - do not manage it here
                # If that switch does not exist on your machine, you should define an External switch and set its name here
                # @{ Name = 'Wifi-HyperV-VSwitch'; Type = 'External'; NetAdapterName = 'WiFi'; AllowManagementOS = $true; }
            )

            # DSCResource = @(
            #     @{ Name = 'xActiveDirectory'; RequiredVersion = '2.17.0.0'; }
            #     @{ Name = 'xComputerManagement'; RequiredVersion = '4.1.0.0'; }
            #     @{ Name = 'xDhcpServer'; RequiredVersion = '1.6.0.0'; }
            #     @{ Name = 'xDnsServer'; RequiredVersion = '1.7.0.0'; }
            #     @{ Name = 'xNetworking'; RequiredVersion = '5.5.0.0'; }
            #     @{ Name = 'xSmbShare'; RequiredVersion = '2.0.0.0'; }
            # )
        }
    }
}
