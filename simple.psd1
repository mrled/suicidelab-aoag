@{
    AllNodes = @(
        @{
            NodeName                    = '*';
            # AddressFamily               = 'IPv4';
            # DnsServerAddress            = '10.0.0.1';
            # DomainName                  = 'aoaglab.vlack.com';
            PSDscAllowPlainTextPassword = $true;
            #CertificateFile             = "$env:AllUsersProfile\Lability\Certificates\LabClient.cer";
            #Thumbprint                  = 'AAC41ECDDB3B582B133527E4DE0D2F8FEB17AAB2';
            PSDscAllowDomainUser        = $true; # Removes 'It is not recommended to use domain credential for node X' messages
            Lability_SwitchName         = 'Wifi-HyperV-Vswitch';
            Lability_ProcessorCount     = 2;
            Lability_StartupMemory      = 3GB;
            Lability_Media              = "2016_x64_Standard_EN_Eval"

            Lability_HardDiskDrive   = @(
                @{
                    Generation = 'VHDX'
                    Type = 'Dynamic'
                    MaximumSizeBytes = 50GB;
                }
            )
            CustomBootStrap = @'
                #### From the default node bootstrap code, according to `get-help about_Bootstrap`
                NET USER Administrator /active:yes;
                Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope LocalMachine -Force;
                Enable-PSRemoting -SkipNetworkProfileCheck -Force;
                #### Custom additions for this lab
                # Enable verbose boot so we can see what's going on
                Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name VerboseBoot -Value 1 -Type DWord -Force;
'@
        }
        @{
            NodeName                = 'SIMPL-TEST-1';
            Lability_ProcessorCount = 2;
        }
    )
    NonNodeData = @{
        Lability = @{
            DSCResource = @(
                @{ Name = 'xActiveDirectory'; RequiredVersion = '2.17.0.0'; }
                @{ Name = 'xComputerManagement'; RequiredVersion = '4.1.0.0'; }
                @{ Name = 'xDhcpServer'; RequiredVersion = '1.6.0.0'; }
                @{ Name = 'xDnsServer'; RequiredVersion = '1.7.0.0'; }
                @{ Name = 'xNetworking'; RequiredVersion = '5.5.0.0'; }
                @{ Name = 'xSmbShare'; RequiredVersion = '2.0.0.0'; }
            )
        }
    }
}
