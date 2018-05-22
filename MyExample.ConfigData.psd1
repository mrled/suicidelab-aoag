@{
    AllNodes = @(
        @{
            NodeName = '*';
            InterfaceAlias = 'Ethernet';
            PSDscAllowPlainTextPassword = $true;
            Lability_SwitchName = 'Wifi-HyperV-VSwitch';
        }
        @{
            NodeName = 'MYEX1';
            Lability_Media = '2016_x64_Datacenter_EN_Eval';
            Lability_ProcessorCount = 2;
            Lability_StartupMemory = 2GB;
        }
    );
    NonNodeData = @{
        Lability = @{
            DSCResource = @(
                @{ Name = 'xNetworking'; RequiredVersion = '5.5.0.0'; }
                @{ Name = 'xPSDesiredStateConfiguration'; RequiredVersion = '6.0.0.0'; }
            )
        };
    };
};
