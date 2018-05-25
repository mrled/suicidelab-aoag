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
        }
        @{
            NodeName                = 'AOAGLAB-DC1';
            IPAddress               = '10.0.0.1/24';
            DnsServerAddress        = '127.0.0.1';
            Role                    = 'DC';
            Lability_ProcessorCount = 2;
            Lability_Resource           = @(
                'Firefox'
            )
        }
        @{
            NodeName                     = 'AOAGLAB-EDGE1';
            Role                         = 'EDGE'
            IPAddress                    = '10.0.0.2/24';

            SecondaryDnsServerAddress    = '1.1.1.1';
            SecondaryInterfaceAlias      = 'Ethernet 2';
            SecondaryDnsConnectionSuffix = 'c4dq.com'

            # These switches appear to get attached to the VM in _random_ order :/ - see readme
            Lability_SwitchName          = @('Wifi-HyperV-VSwitch', 'AOAGLAB-CORPNET')
            # Lability_SwitchName          = @('AOAGLAB-CORPNET', 'Wifi-HyperV-VSwitch')
            Lability_ProcessorCount     = 2
            Lability_Resource           = @(
                'Firefox'
            )
        }
        # @{
        #     NodeName                  = 'AOAGLAB-WEB1';
        #     IPAddress                 = '10.0.0.3/24';
        #     Role                      = 'WEB';
        #     Lability_ProcessorCount     = 1;
        # }
        # @{
        #     NodeName                  = 'AOAGLAB-SQL1';
        #     IPAddress                 = '10.0.0.10/24';
        #     Role                      = 'SQL';
        #     Lability_ProcessorCount     = 1;
        # }
        # @{
        #     NodeName                  = 'AOAGLAB-SQL2';
        #     IPAddress                 = '10.0.0.11/24';
        #     Role                      = 'SQL';
        #     Lability_ProcessorCount     = 1;
        # }
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

            DSCResource = @(
                @{ Name = 'xActiveDirectory'; RequiredVersion = '2.17.0.0'; }
                @{ Name = 'xComputerManagement'; RequiredVersion = '4.1.0.0'; }
                @{ Name = 'xDhcpServer'; RequiredVersion = '1.6.0.0'; }
                @{ Name = 'xDnsServer'; RequiredVersion = '1.7.0.0'; }
                @{ Name = 'xNetworking'; RequiredVersion = '5.7.0.0'; }
                @{ Name = 'xSmbShare'; RequiredVersion = '2.0.0.0'; }
            )

            Resource = @(
                @{
                    Id = 'Firefox'
                    Filename = 'Firefox-Latest.exe'
                    Uri = 'https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US'
                }
            )
        }
    }
}
