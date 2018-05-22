Configuration MyExample {
<#
    Requires the following DSC resources:

        xNetworking:                  https://github.com/PowerShell/xNetworking
        xPSDesiredStateConfiguration: https://github.com/PowerShell/xPSDesiredStateConfiguration
#>
    param ()

    Import-DscResource -Module xPSDesiredStateConfiguration;
    Import-DscResource -Module xNetworking -ModuleVersion 5.5.0.0;

    node $AllNodes.Where({$true}).NodeName {

        LocalConfigurationManager {

            RebootNodeIfNeeded   = $true;
            AllowModuleOverwrite = $true;
            ConfigurationMode = 'ApplyOnly';
            CertificateID = $node.Thumbprint;
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

        File 'NCSI' {
            DestinationPath = 'C:\KILROY.TXT';
            Type            = 'File';
            Contents        = 'DIS BIH WUZ HURR';
            Ensure          = 'Present';
        }

    } #end nodes ALL

} #end Configuration Example

$configData = "$PSScriptRoot\MyExample.ConfigData.psd1"
$adminCred = New-Object -TypeName PSCredential -ArgumentList @(
    "VALUE_IGNORED",
    ('P@ssword123!' | ConvertTo-SecureString -AsPlainText -Force)
)
$configRoot = Get-LabHostDefault | Select-Object -ExpandProperty ConfigurationPath
MyExample -ConfigurationData $configData -OutputPath $configRoot -Verbose
Test-LabConfiguration -ConfigurationData $configData
Start-LabConfiguration -ConfigurationData $configData -Verbose -Credential $adminCred
Start-Lab -ConfigurationData $configData -Verbose
